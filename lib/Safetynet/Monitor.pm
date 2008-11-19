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

sub initialize {
    my $self        = $_[OBJECT];
    # add states
    $_[KERNEL]->state( 'program'                        => $self );
    # verify programs
    {
        (defined $self->options->{programs})
            or confess "spawn() requires a defined 'programs' parameter storage";
        (ref($self->options->{programs}) 
            and $self->options->{programs}->isa( "Safetynet::Program::Storage" ))
            or confess "spawn() requires a valid 'programs' parameter storage";
        $self->{programs} = $self->options->{programs};
    }
}

my $program_cmds = {
    'list'          => sub { # list( $self )
        return $_[0]->{programs}->retrieve_all;
    }, 
    'add'           => sub { # add( $self, $param )
        my $o = 0;
        eval {
            $o = $_[0]->{programs}->add( Safetynet::Program->new($_[1]) ) ? 1 : 0;
        };
        return $o;
    },
    'remove'        => sub {
        my $o = undef;
        eval {
            $o = $_[0]->{programs}->remove( $_[1] ) ? 1 : 0;
        };
        return $o;
    },
    'settings'      => sub {
        my $o = undef;
        eval {
            $o = $_[0]->{programs}->retrieve( $_[1] );
        };
        return $o;
        
    },
};

sub program {
    my $self        = $_[OBJECT];
    my $postback    = $_[ARG0];
    my $stack       = $_[ARG1];
    my $command     = $_[ARG2] || '';
    my $param       = $_[ARG3];
    my $result      = undef;
    if (exists $program_cmds->{$command}) {
        $result     = { 'result' => $program_cmds->{$command}->($self, $param) };
    }
    else {
        $result     = { 'error' => 'unknown command' };
    }
    # do postback
    $_[KERNEL]->post( 
        $postback->[0], 
        $postback->[1], 
        $stack,
        $result,
    ) or confess $_[STATE] . " state: unable to postback";
}


1;

__END__
