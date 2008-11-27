package Safetynet::Event;
use strict;
use warnings;
use Carp;

use Moose;
use POSIX qw/strftime/;

has 'event' => (
    is          => 'rw',
    isa         => 'Str',
    required    => 1,
);

has 'object' => (
    is          => 'rw',
    isa         => 'Any',
    required    => 1,
);

has 'timestamp' => (
    is          => 'rw',
    isa         => 'Int',
    required    => 1,
    default     => sub { time(); },
);


sub as_string {
    my $self = shift;
    my $o = '';
    $o .= sprintf("event:%s", $self->event);
    $o .= sprintf("object:%s", $self->object);
    $o .= sprintf("timestamp:%s", strftime("%Y%m%dT%H%M%S", localtime($self->timestamp)));
    return $o;
}


no Moose;


1;

__END__

