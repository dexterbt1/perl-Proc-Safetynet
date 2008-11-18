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

has 'command' => (
    is          => 'rw',
    isa         => 'Str',
    required    => 1,
);

has 'autostart' => (
    is          => 'rw',
    isa         => 'Bool',
    required    => 1,
    default     => 0,
);

has 'autorestart' => (
    is          => 'rw',
    isa         => 'Bool',
    required    => 1,
    default     => 0,
);

has 'autorestart_wait' => (
    is          => 'rw',
    isa         => 'Int',
    required    => 1,
    default     => 10,
);

has 'priority' => (
    is          => 'rw',
    isa         => 'Int',
    required    => 1,
    default     => 999,
);

no Moose;

1;

__END__
