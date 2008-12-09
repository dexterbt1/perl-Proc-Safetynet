#!/usr/bin/perl
use strict;

#s program is a simple unix socket client.  It will connect to the
# UNIX socket specified by $rendezvous.  This program is written to
# work with the UnixServer example in POE's cookbook.  While it
# touches upon several POE modules, it is not meant to be an
# exhaustive example of them.  Please consult "perldoc [module]" for
# more details.

use strict;
use warnings;

use Socket qw(AF_UNIX);

use POE;                          # For base features.
use POE::Wheel::SocketFactory;    # To create sockets.
use POE::Wheel::ReadWrite;        # To read/write lines with sockets.
use POE::Wheel::ReadLine;         # To read/write lines on the console.
use POE::Filter::JSON::Incr;
use JSON::XS 2.21;
use Data::Dumper;

# Specify a UNIX rendezvous to use.  This is the location the client
# will connect to, and it should correspond to the location a server
# is listening to.

my $rendezvous = shift @ARGV;

# Create the session that will pass information between the console
# and the server.  The create() constructor maps a number of events to
# the functions that will be called to handle them.  For example, the
# "sock_connected" event will cause the socket_connected() function to
# be called.

my %print_result_of = (
    'list_status' => sub {
        my $inp = shift;
        my $res = $inp->{result};
        my @o = ();
        foreach my $k (keys %$res) {
            push @o, sprintf( "%-20s => %s", $k, $res->{$k}->{is_running} ? "running" : "not running" );
        }
        return @o;
    },
    'info_status' => sub {
        my $inp = shift;
        my $res = $inp->{result};
        my @o = ();
        if (exists $inp->{error}) {
            push @o, sprintf("ERROR: (status): %s", $inp->{error}->{message} );
        }
        if (exists $res->{is_running}) {
            push @o, sprintf( "%s", $res->{is_running} ? "running" : "not running" );
        }
        return @o;
    },
    'start_program' => sub {
        my $inp = shift;
        my $res = $inp->{result};
        my @o = ();
        if (exists $inp->{error}) {
            push @o, sprintf("ERROR: (start): %s", $inp->{error}->{message} );
        }
        if ($res) {
            push @o, "start OK.";
        }
        return @o;
    },
    'stop_program' => sub {
        my $inp = shift;
        my $res = $inp->{result};
        my @o = ();
        if (exists $inp->{error}) {
            push @o, sprintf("ERROR: (stop): %s", $inp->{error}->{message} );
        }
        if ($res) {
            push @o, "stop OK.";
        }
        return @o;
    },
    'commit_programs' => sub {
        my $inp = shift;
        my $res = $inp->{result};
        my @o = ();
        if (exists $inp->{error}) {
            push @o, sprintf("ERROR: (commit): %s", $inp->{error}->{message} );
        }
        if ($res) {
            push @o, "commit OK.";
        }
        return @o;
    },
    'add_program' => sub {
        my $inp = shift;
        my $res = $inp->{result};
        my @o = ();
        if (exists $inp->{error}) {
            push @o, sprintf("ERROR: (add): %s", $inp->{error}->{message} );
        }
        if ($res) {
            push @o, "add OK.";
        }
        return @o;
    },
    'remove_program' => sub {
        my $inp = shift;
        my $res = $inp->{result};
        my @o = ();
        if (exists $inp->{error}) {
            push @o, sprintf("ERROR: (remove): %s", $inp->{error}->{message} );
        }
        if ($res) {
            push @o, "remove OK.";
        }
        return @o;
    },
    'list_programs' => sub {
        my $inp = shift;
        my $res = $inp->{result};
        my @o = ();
        my $i = 1;
        foreach my $p (@$res) {
            push @o, sprintf( "%s", $p->{name});
            delete $p->{name};
            foreach my $k (sort keys %$p) {
                push @o, sprintf( "      %-20s = %s", $k, $p->{$k});
            }
            $i++;
        }
        return @o;
    },
    'info_program' => sub {
        my $inp = shift;
        my $res = $inp->{result};
        my @o = ();
        my $p = $res;
        if (exists $inp->{error}) {
            push @o, sprintf("ERROR: (info): %s", $inp->{error}->{message} );
        }
        if (exists $p->{name}) {
            push @o, sprintf( "%s", $p->{name});
            delete $p->{name};
            foreach my $k (sort keys %$p) {
                push @o, sprintf( "      %-20s = %s", $k, $p->{$k});
            }
        }
        return @o;
    },
);

POE::Session->create
  ( inline_states =>
      { _start => \&client_init,
        sock_connected => \&socket_connected,
        sock_error     => \&socket_error,
        sock_input     => \&socket_input,
        cli_input      => \&console_input,
      },
  );

# Run the client until it is finished, then exit because we're done.
# The rest of this program consists of event handlers.

$poe_kernel->run();
exit 0;

# The client_init() function is called when POE sends a "_start" event
# to the session.  This happens automatically whenever a session is
# created, and its purpose is to notify your code when it can begin
# doing things.

# Here we create the SocketFactory that will connect a socket to the
# server.  The socket factory is tightly associated with its session,
# so it is kept in the session's private storage space (its "heap").

# The socket factory is configured to emit two events: On a successful
# connection, it sends a "sock_connected" event containing the new
# socket.  On a failure, it sends "sock_error" along with information
# about the problem.

sub client_init {
    my $heap = $_[HEAP];

    $heap->{connect_wheel} = POE::Wheel::SocketFactory->new
      ( SocketDomain => AF_UNIX,
        RemoteAddress => $rendezvous,
        SuccessEvent  => 'sock_connected',
        FailureEvent  => 'sock_error',
      );
    $heap->{cmd_sent} = { };
}

# socket_connected() is called when the session receives a
# "sock_connected" event.  That event is generated by the session's
# SocketFactory object when it has connected to a server.  The newly
# connected socket is passed in ARG0.

# This function discards the SocketFactory object since its purpose
# has been fulfilled.  It then creates two new objects: a ReadWrite
# wheel to talk with the socket, and a ReadLine wheel to talk with the
# console.  POE::Wheel::ReadLine was named after Term::ReadLine, by
# the way.  Once socket_connected() has set us up the wheels, it calls
# ReadLine's get() method to prompt the user for input.

sub socket_connected {
    my ( $heap, $socket ) = @_[ HEAP, ARG0 ];

    delete $heap->{connect_wheel};
    $heap->{io_wheel} = POE::Wheel::ReadWrite->new
      ( Handle => $socket,
        InputEvent => 'sock_input',
        ErrorEvent => 'sock_error',
        Filter      => POE::Filter::JSON::Incr->new(
            errors      => 1,
            json        => JSON::XS->new->utf8->allow_blessed->convert_blessed,
        ),
      );

    $heap->{cli_wheel} = POE::Wheel::ReadLine->new( InputEvent => 'cli_input' );
    $heap->{cli_wheel}->get("=> ");
}

# socket_input() is called to handle "sock_input" events.  These
# events are provided by the POE::Wheel::ReadWrite object that was
# created in socket_connected().

# socket_input() moves information from the socket to the console.



sub socket_input {
    my ( $heap, $input ) = @_[ HEAP, ARG0 ];
    my $cmdid = $input->{id};
    my $cmd = (defined $cmdid) ? delete $heap->{cmd_sent}->{$cmdid} : undef;

    if (defined $cmd) {
        my $method = $cmd->{method};
        my @disp = $print_result_of{$method}->($input);
        foreach my $line (@disp) {
            $heap->{cli_wheel}->put($line);
        }
    }
    #$heap->{cli_wheel}->put("Server Said: ".Dumper($input));
}

# socket_error() is called to handle "sock_error" events.  These
# events can come from two places: The SocketFactory will send it if a
# connection fails, and the ReadWrite object will send it if a read or
# write error occurs.

# The most common way to handle I/O errors is to shut down the sockets
# having problems.  Here we'll delete all our wheels so the program
# can shut down gracefully.

# ARG0 contains the name of the syscall that failed.  It is often
# "connect" or "bind" or "read" or "write".  ARG1 and ARG2 contain the
# numeric and descriptive contents of $! at the time of the failure.

sub socket_error {
    my ( $heap, $syscall, $errno, $error ) = @_[ HEAP, ARG0 .. ARG2 ];
    $error = "Normal disconnection." unless $errno;
    delete $heap->{connect_wheel};
    delete $heap->{io_wheel};
    delete $heap->{cli_wheel};
    die "Client socket encountered $syscall error $errno: $error\n";
}

# Finally, the console_input() function is called to handle
# "cli_input" events.  These events are created when
# POE::Wheel::ReadLine (created in socket_connected()) receives user
# input from the console.

# Plain input is registered with ReadLine's input history, echoed back
# to the console, and sent to the server.  Exceptions, such as when
# the user presses Ctrl+C to interrupt the program, are also handled.

# POE::Wheel::ReadLine events include two parameters other than the
# usual KERNEL, HEAP, etc.  The ARG0 parameter contains plain input.
# If that's undefined, then ARG1 will contain an exception.

sub console_input {
    my ( $heap, $input, $exception ) = @_[ HEAP, ARG0, ARG1 ];


    if ( defined $input ) {
        my $cmd;
        $input =~ s/^\s*//g; # trim
        $input =~ s/\s*$//g;
        
        SWITCH: {
            ($input eq 'status-all') and do {
                my $id = next_id(); 
                $cmd = { "method" => "list_status", "params" => [ ], "id" => $id };
                $heap->{cmd_sent}->{$id} = $cmd;
                last SWITCH;
            };
            ($input =~ /^status\s+(\w+)$/) and do {
                my $id = next_id(); 
                $cmd = { "method" => "info_status", "params" => [ $1 ], "id" => $id };
                $heap->{cmd_sent}->{$id} = $cmd;
                last SWITCH;
            };
            ($input =~ /^start\s+(\w+)$/) and do {
                my $id = next_id(); 
                $cmd = { "method" => "start_program", "params" => [ $1 ], "id" => $id };
                $heap->{cmd_sent}->{$id} = $cmd;
                last SWITCH;
            };
            ($input =~ /^stop\s+(\w+)$/) and do {
                my $id = next_id(); 
                $cmd = { "method" => "stop_program", "params" => [ $1 ], "id" => $id };
                $heap->{cmd_sent}->{$id} = $cmd;
                last SWITCH;
            };
            ($input =~ /^info-all$/) and do {
                my $id = next_id(); 
                $cmd = { "method" => "list_programs", "params" => [ ], "id" => $id };
                $heap->{cmd_sent}->{$id} = $cmd;
                last SWITCH;
            };
            ($input =~ /^add\s+(\{.*\})$/) and do {
                my $id = next_id(); 
                my $p = $1;
                eval {
                    $p = JSON::XS::decode_json( $p );
                };
                if ($@) {
                    $heap->{cli_wheel}->put("ERROR: ".clean_eval_error($@));
                    last SWITCH;
                }
                $cmd = { "method" => "add_program", "params" => [ $p ], "id" => $id };
                $heap->{cmd_sent}->{$id} = $cmd;
                last SWITCH;
            };
            ($input =~ /^remove\s+(\w+)$/) and do {
                my $id = next_id(); 
                $cmd = { "method" => "remove_program", "params" => [ $1 ], "id" => $id };
                $heap->{cmd_sent}->{$id} = $cmd;
                last SWITCH;
            };
            ($input =~ /^info\s+(\w+)$/) and do {
                my $id = next_id(); 
                $cmd = { "method" => "info_program", "params" => [ $1 ], "id" => $id };
                $heap->{cmd_sent}->{$id} = $cmd;
                last SWITCH;
            };
            ($input =~ /^commit$/) and do {
                my $id = next_id(); 
                $cmd = { "method" => "commit_programs", "params" => [ ], "id" => $id };
                $heap->{cmd_sent}->{$id} = $cmd;
                last SWITCH;
            };
            
            last SWITCH;
        }
        $heap->{cli_wheel}->addhistory($input);
        #$heap->{cli_wheel}->put("You Said: $input");
        if (defined $cmd) {
            $heap->{io_wheel}->put($cmd);
        }
        else {
            $heap->{cli_wheel}->put("ERROR: Invalid Command ($input)");
        }
    } elsif ( $exception eq 'cancel' ) {
        $heap->{cli_wheel}->put("Canceled.");
    } else {
        $heap->{cli_wheel}->put("Bye.");
        delete $heap->{cli_wheel};
        delete $heap->{io_wheel};
        return;
    }

    # Prompt for the next bit of input.
    $heap->{cli_wheel}->get("=> ");
}



my $idcount = 0;
sub next_id {
    $idcount++;
}


sub clean_eval_error {
    my $err = shift;
    my ($e) = ($err =~ m/^(.*)\s+at\s+.*\s+line\s+\d+/);
    return $e;
}
