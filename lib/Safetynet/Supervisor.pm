package Safetynet::Supervisor;
use strict;
use warnings;
use Wyrls::AbstractWorker;
use base qw/Wyrls::AbstractWorker/;

use Carp;
use Data::Dumper;
use POE::Kernel;
use POE::Session;
use IO::Handle;
use Scalar::Util qw/blessed reftype/;

use Safetynet::Event;
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
    $_[KERNEL]->state( 'info_program'                   => $self );
    $_[KERNEL]->state( 'info_status'                    => $self );
    $_[KERNEL]->state( 'start_program'                  => $self );
    $_[KERNEL]->state( 'stop_program'                   => $self );
    $_[KERNEL]->state( 'stop_program_timeout'           => $self );
    $_[KERNEL]->state( 'nop'                            => $self );

    $_[KERNEL]->state( 'sig_ignore'                     => $self );
    $_[KERNEL]->state( 'sig_CHLD'                       => $self );
    $_[KERNEL]->state( 'sig_PIPE'                       => $self );

    $_[KERNEL]->state( 'tell_event'                     => $self );
    $_[KERNEL]->state( 'bcast_system_error'             => $self );
    $_[KERNEL]->state( 'bcast_process_started'          => $self );
    $_[KERNEL]->state( 'bcast_process_stopped'          => $self );
    # trap signals
    $_[KERNEL]->sig( PIPE   => 'sig_PIPE' );
    $_[KERNEL]->sig( INT    => 'sig_ignore' );
    $_[KERNEL]->sig( HUP    => 'sig_ignore' );
    $_[KERNEL]->sig( TERM   => 'sig_ignore' );
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
    $self->{killed} = { };
    foreach my $p (@{ $self->{programs}->retrieve_all() }) {
        $self->monitor_add_program( $p );
    }
    $self->yield( 'start_work' );
}


sub heartbeat {
    my $self        = $_[OBJECT];
    $_[KERNEL]->delay( 'heartbeat' => 1 );
}


sub start_work {
    my $self        = $_[OBJECT];
    # start all autostart processes
    foreach my $p (@{ $self->{programs}->retrieve_all() }) {
        if ($p->autostart) {
            $self->yield( 'start_program', [ $self->alias, 'nop' ], [ $p ], $p->name );
        }
    }
}


sub nop {
    # do nothing
}


sub sig_ignore {
    # ignore signals for now ...
    # TODO: bcast this as event
    warn "$$ signalled\n";
    $_[KERNEL]->sig_handled();
}


sub sig_PIPE {
    # ignore signals for now ...
    warn "$$ signalled SIGPIPE\n";
    $_[KERNEL]->yield( 'bcast_system_error', "got SIGPIPE signal" );
    $_[KERNEL]->sig_handled();
}


# SIGCHLD handler
sub sig_CHLD {
    my $self        = $_[OBJECT];
    my $name        = $_[ARG0];
    my $pid         = $_[ARG1];
    my $exit_val    = $_[ARG2];
    ##print STDERR "SIGCHLD: $name, $pid, $exit_val\n";
    # clear status
    my $program_name = '';
    foreach my $ps_key (keys %{ $self->{monitored} }) {
        my $ps = $self->{monitored}->{$ps_key};
        my $pspid = $ps->pid() || 0;
        if ($pspid == $pid) {
            ##print STDERR "post: pid=$pid, pspid=".$ps->pid(), "\n";
            $ps->pid(0);
            $ps->stopped_since( time() );
            $ps->is_running( 0 );
            delete $ps->{_stdin};
            $program_name = $ps_key;
            last;
        }
    }
    # postback if killed
    if (exists $self->{killed}->{$program_name}) {
        my $pb = delete $self->{killed}->{$program_name};
        $_[KERNEL]->yield( 'do_postback', $pb->[0], $pb->[1], 1 );
        $_[KERNEL]->delay( 'stop_program_timeout' ); # cancel
    }
    # schedule for restart, if applicable
    my $prog = $self->{programs}->retrieve( $program_name );
    if (defined $prog) {
        # an event has happened, a process has been started ...
        $_[KERNEL]->yield( 'bcast_process_stopped', $prog, $exit_val, 1 );
        # autorestart if applicable
        if ($prog->autorestart()) {
            $_[KERNEL]->delay_add( 
                'start_program' => 
                $prog->autorestart_wait(), 
                [ $self->alias, 'nop'], 
                [ $prog, $exit_val ], 
                $program_name,
            );
        }
    }
}


sub do_postback {
    my $postback    = $_[ARG0];
    my $stack       = $_[ARG1];
    my $result      = $_[ARG2];
    # filter the result to output only public information
    if (defined($result) and blessed($result)) {
        # FIXME: maybe we can refactor this later into its own routine
        if (reftype($result) eq 'HASH') {
            my $class = ref($result);
            my $o = { };
            foreach my $k (keys %$result) {
                # we'd like to filter out the private keys 
                # starting with underscores "_"
                if ($k !~ m/^_/) {  
                    $o->{$k} = $result->{$k};
                }
            }
            $result = $class->new($o);
        }
    }
    $_[KERNEL]->post( 
        $postback->[0], 
        $postback->[1], 
        $stack,
        { result => $result },
    ) or warn "unable to postback: $!";
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
    # TODO: check whitelist
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

sub info_program {
    my $program_name = $_[ARG2];
    my $o = undef;
    eval {
        $o = $_[OBJECT]->{programs}->retrieve( $program_name );
    };
    $_[KERNEL]->yield( 'do_postback', @_[ARG0, ARG1], $o );
}

# process management
sub info_status { 
    my $program_name = $_[ARG2];
    my $o = undef;
    if (exists $_[OBJECT]->{monitored}->{$program_name}) {
        $o = $_[OBJECT]->{monitored}->{$program_name};
    }
    $_[KERNEL]->yield( 'do_postback', @_[ARG0, ARG1], $o );
}

sub start_program { 
    my $program_name = $_[ARG2];
    my $p = undef;
    my $o = 0;
    # TODO: don't start if already started
    SPAWN: {
        if (exists $_[OBJECT]->{monitored}->{$program_name}) {
            my $ps = $_[OBJECT]->{monitored}->{$program_name};
            if ($ps->is_running) {
                # already running
                last SPAWN;
            }
            $p = $_[OBJECT]->{programs}->retrieve($program_name);
            my $command = $p->command;

            # pipe: simulate open(FOO, "|-")
            # -----
            my $parentfh;
            my $childfh;
            if ($p->eventlistener) {
                # pipe only if this is an eventlistener process
                $parentfh = IO::Handle->new;
                eval {
                    pipe $childfh, $parentfh 
                        or die $!;
                };
                if ($@) {
                    warn "$$: unable to pipe: $@";
                    $_[KERNEL]->yield( 'bcast_system_error', "unable to create pipe: $@", $p );
                    last SPAWN; 
                }
            }
            # fork
            # ----
            my $pid = fork;
            if (not defined $pid) {
                warn "$$: unable to fork: $!";
                $_[KERNEL]->yield( 'bcast_system_error', "unable to fork: $@", $p );
                last SPAWN;
            }
            if ($pid) {
                # parent here
                if ($p->eventlistener) {
                    close $childfh;
                }
                $_[KERNEL]->sig_child( $pid, 'sig_CHLD' );
                $ps->is_running( 1 );
                $ps->pid( $pid );
                $ps->started_since( time() );
                # trap autoflush handle errors
                eval {
                    if (defined $parentfh) {
                        $parentfh->autoflush(1);
                    }
                    $ps->{_stdin} = $parentfh;
                    ##print STDERR "$$: started $program_name, pid=$pid\n";
                    $o = 1;
                };
                if ($@) {
                    warn "$$: setup of child stdin failed: $@";
                    last SPAWN;
                }
            }
            else {
                # child here ... a point of no return # TODO: redirect STDERR, STDOUT ...
                # TODO: check whitelist
                # TODO: apply uid/gid changes 
                # TODO: apply chroot
                # assume command was already sanitized
                if ($p->eventlistener) {
                    close $parentfh;
                    open(STDIN, "<&=" . fileno($childfh)) 
                        or die "child unable to open stdin";
                }
                my ($cmd) = ($command =~ /^(.*)$/);
                exec $cmd
                    or exit(100);
            }
        }
    }
    if ($o) {
        # an event has happened, a process has been started
        $_[KERNEL]->yield( 'bcast_process_started', $p, 1 );
    }
    $_[KERNEL]->yield( 'do_postback', @_[ARG0, ARG1], $o );
}

sub stop_program {
    my $program_name = $_[ARG2];
    if (exists $_[OBJECT]->{monitored}->{$program_name}) {
        my $ps = $_[OBJECT]->{monitored}->{$program_name};
        if ( ($ps->is_running) and (not exists $_[OBJECT]->{killed}->{$program_name}) ) {
            # defer postback until either SIGCHLD or time out waiting
            $_[OBJECT]->{killed}->{$program_name} = [ $_[ARG0], $_[ARG1], ];
            # kill the process
            my $o = kill 'TERM', $ps->pid;
            if ($o > 0) {
                # okay, we've signalled the process, we now have to wait for SIGCHLD to occur
                #   or timeout
                $_[KERNEL]->delay( 'stop_program_timeout' => 10, @_[ARG0, ARG1], $program_name );
            }
            else {
                # signalling did not work this time
                $_[KERNEL]->yield( 'do_postback', @_[ARG0, ARG1], 0 );
            }
        }
        else {
            # not running or already issued a kill
            $_[KERNEL]->yield( 'do_postback', @_[ARG0, ARG1], 0 );
        }
    }
    else {
        # non-existent
        $_[KERNEL]->yield( 'do_postback', @_[ARG0, ARG1], 0 );
    }
}

sub stop_program_timeout {
    my $program_name = $_[ARG2];
    if (exists $_[OBJECT]->{killed}->{$program_name}) {
        delete $_[OBJECT]->{killed}->{$program_name};
        $_[KERNEL]->yield( 'do_postback', @_[ARG0, ARG1], 0 );
    }
}


sub shutdown {
    my $self        = $_[OBJECT];
    $_[KERNEL]->delay( 'heartbeat' );
    $self->SUPER::shutdown( @_[1..$#_]);
}

# ============== Event Broadcasters

# POE_ARGS( $p, $ps, $event )
# - sends the event to one event listener
sub tell_event {
    my $self    = $_[OBJECT];
    my $p       = $_[ARG0];
    my $ps      = $_[ARG1];
    my $event   = $_[ARG2];
    # write to STDIN of event listener
    my $stdin   = $ps->{_stdin};
    if (defined $stdin) {
        print $stdin $event->as_string."\n";
    }
}


sub _do_event_bcast { # non-POE
    my $self = shift;
    my $event = shift;
    foreach my $p (@{ $self->{programs}->retrieve_all } ) {
        my $pname = $p->name;
        my $ps = $self->{monitored}->{$pname};
        if ($ps->is_running and $p->eventlistener) {
            $self->yield( 'tell_event' => $p, $ps, $event );
        }
    }
}


sub bcast_system_error {
    my $self    = $_[OBJECT];
    my $message = $_[ARG0];
    my $p       = $_[ARG1];
    my $object  = '@SYSTEM'; #default
    if (defined $p) {
        $object = $p->name;
    }
    my $ev = Safetynet::Event->new(
        event       => 'system_error',
        object      => $object,
        message     => $message,
    );
    $self->_do_event_bcast( $ev );
}


sub bcast_process_started {
    my $self    = $_[OBJECT];
    my $p       = $_[ARG0];
    my $started = $_[ARG1];
    if ($started) {
        my $ev = Safetynet::Event->new(
            event       => 'process_started',
            object      => $p->name,
        );
        $self->_do_event_bcast( $ev );
    }
}


sub bcast_process_stopped {
    my $self    = $_[OBJECT];
    my ($p, $exit_val, $stopped) = @_[ARG0, ARG1, ARG2];
    if ($stopped) {
        my $ev = Safetynet::Event->new(
            event       => 'process_stopped',
            object      => $p->name,
        );
        $self->_do_event_bcast( $ev );
    }
}

# ==============


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



1;

__END__
