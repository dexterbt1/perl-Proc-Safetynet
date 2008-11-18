package Safetynet::ProgramStatus;
use strict;
use warnings;
use Carp;

use Moose;

has 'is_running' => (
    is          => 'rw',
    isa         => 'Bool',
    required    => 1,
    default     => 0,
);

has 'started_since' => (
    is          => 'rw',
    isa         => 'Int',
    required    => 1,
    default     => sub { time(); },
);

has 'pid'       => (
    is          => 'rw',
    isa         => 'Int',
    required    => 1,
    default     => 0,
);

no Moose;


1;

__END__
