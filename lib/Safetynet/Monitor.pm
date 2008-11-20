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
    $_[KERNEL]->state( 'program'                        => $self, 'program_api' );
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



my $program_cmds = {
    # program provisioning
    'list'          => sub { # list( $self )
        return $_[0]->{programs}->retrieve_all;
    }, 
    'add'           => sub { # add( $self, $param )
        my $o = 0;
        eval {
            my $p = Safetynet::Program->new($_[1]);
            $o = $_[0]->{programs}->add( $p ) ? 1 : 0;
            if ($o) { 
                # track status
                $_[0]->monitor_add_program( $p );
            }
        };
        return $o;
    },
    'remove'        => sub {
        my $o = undef;
        eval {
            $o = $_[0]->monitor_remove_program( $_[1] ) ? 1 : 0;
        };
        if ($@) { $o = 0; }
        return $o;
    },
    'settings'      => sub {
        my $o = undef;
        eval {
            $o = $_[0]->{programs}->retrieve( $_[1] );
        };
        return $o;
    },
    # process management
    'status'        => sub { # status( $self, $program_name )
        my $o = undef;
        if (exists $_[0]->{monitored}->{$_[1]}) {
            $o = $_[0]->{monitored}->{$_[1]};
        }
        return $o;
    },
    'start'         => sub { # start( $self, $program_name )
        my $o = 0;
        if (exists $_[0]->{monitored}->{$_[1]}) {
            $o = $_[0]->monitor_start_program( $_[1] );
        }
        return $o;
    },
};

# api: program command processing
sub program_api {
    my $self        = $_[OBJECT];
    my $postback    = $_[ARG0];
    my $stack       = $_[ARG1];
    my $command     = $_[ARG2] || '';
    my $param       = $_[ARG3];
    my $result      = undef;
    if (exists $program_cmds->{$command}) {
        my $o           = $program_cmds->{$command}->($self, $param);
        $result         = { 'result' => $o };
    }
    else {
        $result         = { 'error' => 'unknown command' };
    }
    # do postback
    $_[KERNEL]->post( 
        $postback->[0], 
        $postback->[1], 
        $stack,
        $result,
    ) or confess $_[STATE] . " state: unable to postback";
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
                # child here ... so point of no return
                # TODO: redirect STDERR, STDOUT ...
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


1;

__END__
