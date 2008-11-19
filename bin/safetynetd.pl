#!/usr/bin/perl -wT
use strict;
use warnings;

use Safetynet;
use Safetynet::Program::Storage::TextFile;

use Config::General;
use Data::Dumper;

my $usage = <<EOF;
Usage: $0 <config_file>
EOF

my $config;
{
    my $config_file = shift @ARGV || '';
    (-e $config_file)
        or die $usage;
    my $rc = Config::General->new( $config_file );
    $config = { $rc->getall() };
}

my $programs = Safetynet::Program::Storage::TextFile->new(
    file        => $config->{programs},
);
$programs->reload();

# ---------

my $monitor = Safetynet::Monitor->spawn(
    alias           => q{MONITOR},
    programs        => $programs,
);
#if (exists $config->{unix_server}) {
#    Safetynet::UnixServer->spawn(
#        alias       => q{UNIXSERVER},
#        monitor     => q{MONITOR},
#        %{ $config->{unix_server} },
#    );
#}

POE::Kernel->run();

__END__
