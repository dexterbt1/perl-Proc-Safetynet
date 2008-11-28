package Safetynet::Shell::Basic;
use strict;
use warnings;
use Wyrls::AbstractWorker;
use base qw/Wyrls::AbstractWorker/;

use Carp;
use Data::Dumper;
use POE::Kernel;
use POE::Session;

use Safetynet::Event;
use Safetynet::Program;
use Safetynet::ProgramStatus;


sub initialize {
    my $self        = $_[OBJECT];
    $_[KERNEL]->state( 'session_input'              => $self );
}


sub session_input {
    my $self        = $_[OBJECT];
    my $postback    = $_[ARG0];
    my $stack       = $_[ARG1];
    $_[KERNEL]->post( $postback->[0], $postback->[1], $stack, 'result-here' );
}



1;

__END__
