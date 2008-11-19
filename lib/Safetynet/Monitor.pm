package Safetynet::Monitor;
use strict;
use warnings;
use Wyrls::AbstractWorker;
use base qw/Wyrls::AbstractWorker/;

use Carp;
use Data::Dumper;
use POE::Kernel;
use POE::Session;

sub initialize {
    my $self        = $_[OBJECT];
    # add states
    $_[KERNEL]->state( 'program_list'                   => $self );
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


sub program_list {
    my $self        = $_[OBJECT];
    my $postback    = $_[ARG0];
    my $stack       = $_[ARG1];
    my $list        = $self->{programs}->retrieve_all;
    $_[KERNEL]->post( 
        $postback->[0], 
        $postback->[1], 
        $stack,
        $list
    ) or confess $_[STATE] . " state: unable to postback";
}


1;

__END__
