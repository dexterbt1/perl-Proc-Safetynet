package Safetynet::Program;
use strict;
use warnings;
use Carp;

use Moose;

has 'name' => (
    is          => 'rw',
    isa         => 'Str',
    required    => 1,
);

has 'executable' => (
    is          => 'rw',
    isa         => 'Str',
    required    => 1,
);

no Moose;

1;

__END__
