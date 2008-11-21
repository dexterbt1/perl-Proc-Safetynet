package Safetynet::Monitor;
use strict;
use warnings;
use Wyrls::AbstractWorker;
use base qw/Wyrls::AbstractWorker/;

use Carp;
use Data::Dumper;
use POE::Kernel;
use POE::Session;

use Safetynet::Program;
use Safetynet::ProgramStatus;
use POSIX ':sys_wait_h';

sub initialize {
    my $self        = $_[OBJECT];
    # add states
    $_[KERNEL]->state( 'heartbeat'                      => $self );
    $_[KERNEL]->state( 'do_postback'                    => $self );
    $_[KERNEL]->state( 'list_programs'                  => $self );
    $_[KERNEL]->state( 'add_program'                    => $self );
    $_[KERNEL]->state( 'remove_program'                 => $self );
    $_[KERNEL]->state( 'get_program'                    => $self );
    $_[KERNEL]->state( 'view_status'                    => $self );
    $_[KERNEL]->state( 'start_program'                  => $self );
    $_[KERNEL]->state( 'stop_program'                   => $self );
    # verify programs
    {
        (defined $self->options->{programs})
            or confess "spawn() requires a defined 'programs' parameter";
        (ref($self->options->{programs}) 
            and $self->options->{programs}->isa( "Safetynet::Program::Storage" ))
            or confess "spawn() requires a valid 'programs' parameter";
        $self->{programs} = $self->options->{programs};
    }
    # verify binpath
    {
        (defined $self->options->{binpath})
            or confess "spawn() requires a defined 'binpath' parameter";
        my @p = ();
        foreach my $tp (split /:/, $self->options->{binpath}) {
            my ($path) = ($tp =~ /^(.*)$/);
            (-d $path)
                or confess "binpath expects valid directories";
            ($path !~ /\.\.\//)
                or confess "binpath does not allow (..) directories";
            ($path =~ /^\//)
                or confess "binpath only allows absolute directories";
            push @p, $path;
        }
        $ENV{PATH} = join(':', @p);
    }
    # start monitoring
    $self->{monitored} = { };
    foreach my $p (@{ $self->{programs}->retrieve_all() }) {
        $self->monitor_add_program( $p );
    }
}


sub heartbeat {
    my $self        = $_[OBJECT];
    $_[KERNEL]->delay( 'heartbeat' => 1 );
}


sub start_work {
    my $self        = $_[OBJECT];
    # do nothing
}


sub do_postback {
    my $postback    = $_[ARG0];
    my $stack       = $_[ARG1];
    my $result      = $_[ARG2];
    $_[KERNEL]->post( 
        $postback->[0], 
        $postback->[1], 
        $stack,
        { result => $result },
    ) or confess "unable to postback: $!";
}


# program provisioning
sub list_programs {
    my $result = $_[OBJECT]->{programs}->retrieve_all;
    $_[KERNEL]->yield( 'do_postback', @_[ARG0, ARG1], $result );
} 


sub add_program {
    my $program = $_[ARG2];
    my $o = 0;
    # TODO: sanitize the param
    eval {
        my $p = Safetynet::Program->new($program);
        $o = $_[OBJECT]->{programs}->add( $p ) ? 1 : 0;
        if ($o) { 
            # track status
            $_[OBJECT]->monitor_add_program( $p );
        }
    };
    $_[KERNEL]->yield( 'do_postback', @_[ARG0, ARG1], $o );
}

sub remove_program {
    my $program_name = $_[ARG2];
    my $o = undef;
    eval {
        $_[OBJECT]->monitor_remove_program( $program_name );
        $o = $_[OBJECT]->{programs}->remove( $program_name ) ? 1 : 0;
    };
    if ($@) { $o = 0; }
    $_[KERNEL]->yield( 'do_postback', @_[ARG0, ARG1], $o );
}

sub get_program {
    my $program_name = $_[ARG2];
    my $o = undef;
    eval {
        $o = $_[OBJECT]->{programs}->retrieve( $program_name );
    };
    $_[KERNEL]->yield( 'do_postback', @_[ARG0, ARG1], $o );
}

# process management
sub view_status { 
    my $program_name = $_[ARG2];
    my $o = undef;
    if (exists $_[OBJECT]->{monitored}->{$program_name}) {
        $o = $_[OBJECT]->{monitored}->{$program_name};
    }
    $_[KERNEL]->yield( 'do_postback', @_[ARG0, ARG1], $o );
}

sub start_program { 
    my $program_name = $_[ARG2];
    my $o = 0;
    if (exists $_[OBJECT]->{monitored}->{$program_name}) {
        $o = $_[OBJECT]->monitor_start_program( $program_name );
    }
    $_[KERNEL]->yield( 'do_postback', @_[ARG0, ARG1], $o );
}

sub stop_program {
    my $program_name = $_[ARG2];
    my $o = 0;
    if (exists $_[OBJECT]->{monitored}->{$program_name}) {
        $o = $_[OBJECT]->monitor_stop_program( $program_name );
    }
    $_[KERNEL]->yield( 'do_postback', @_[ARG0, ARG1], $o );
}


sub shutdown {
    my $self        = $_[OBJECT];
    $_[KERNEL]->delay( 'heartbeat' );
    $self->SUPER::shutdown( @_[1..$#_]);
}


sub monitor_add_program { # non-POE
    my $self = shift;
    my $p = shift;
    my $name = $p->name() || '';
    if (not exists $self->{monitored}->{$name}) {
        $self->{monitored}->{$name} 
            = Safetynet::ProgramStatus->new({ is_running => 0 });
        # TODO: start if autostart
    }
}


sub monitor_remove_program { # non-POE
    my $self = shift;
    my $name = shift;
    my $ret  = 0;
    if (exists $self->{monitored}->{$name}) {
        my $ps = $self->{monitored}->{$name};
        if ($ps->is_running) { 
            croak "cannot remove running program"; 
        }
        delete $self->{monitored}->{$name};
        $ret = 1;
    }
    return $ret;
}


# return 1 if success, 0 if failure
sub monitor_start_program { # non-POE
    my $self = shift;
    my $name = shift;
    my $ret  = 0;
    # TODO: don't start if already started
    if (exists $self->{monitored}->{$name}) {
        my $p = $self->{programs}->retrieve($name);
        my $command = $p->command;
        # run
        my $pid = fork;
        if (defined $pid) {
            if ($pid == 0) {
                # child here ... a point of no return
                # TODO: redirect STDERR, STDOUT ...
                # TODO: apply uid/gid changes 
                # TODO: apply chroot
                # assume command was already sanitized
                my ($cmd) = ($command =~ /^(.*)$/);
                exec $cmd
                    or die "cannot exec command [$cmd]";
                exit(100);
            }
            else {
                # parent here
                my $ps = $self->{monitored}->{$name};
                $ps->is_running( 1 );
                $ps->pid( $pid );
                $ps->started_since( time() );
                $ret = 1;
            }
        }
        # else: undef fork means failed start
    }
    return $ret;
}


# return 1 if success, 0 if failure
sub monitor_stop_program { # non-POE
    my $self = shift;
    my $name = shift;
    my $ret  = 0;
    if (exists $self->{monitored}->{$name}) {
        my $ps = $self->{monitored}->{$name};
        if ($ps->is_running) {
            kill 'TERM', $ps->pid;
        }
    }
}



1;

__END__
