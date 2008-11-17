package Safetynet::Program::Storage::TextFile;
use strict;
use warnings;
use Carp;
use Scalar::Util qw/blessed/;

use Moose;

extends 'Safetynet::Program::Storage::Memory';

# NOTE: uses implementation inheritance

has 'file' => (
    is          => 'rw',
    isa         => 'Str',
    required    => 1,
);


sub commit {
    my $self = shift;
    {
        my $filename = $self->file();
        open my $fh, ">$filename"
            or croak "unable to open storage file: $filename: $!";

        my $hr = $self->_children();
        foreach my $k (sort keys %$hr) {
            my $p = $hr->{$k};
            print $fh sprintf("%s:%s\n", $p->name, $p->executable);
        }
        close $fh;
    }
}


sub reload {
    my $self = shift;
    {
        $self->_children({});
        my $filename = $self->file();
        open my $fh, $filename
            or croak "unable to open storage file: $filename: $!";
        while (my $line=<$fh>) {
            chomp $line;
            $line =~ s/^\s*//;
            $line =~ s/\s*$//;
            my ($name, $exec) = split /\s*:\s*/, $line;
            my $o = Safetynet::Program->new( name => $name, executable => $exec );
            $self->_children->{$name} = $o;
        }
        close $fh;
    }
}


1;

__END__
