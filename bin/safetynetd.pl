#!/usr/bin/perl -wT
use strict;
use warnings;

use Safetynet;
use Safetynet::Program::Storage::TextFile;

use Fcntl ':flock';
use Config::General;
use Data::Dumper;

my $usage = <<EOF;
Usage: $0 <config_file>
EOF

my $lockfh;
my $config;
{
    # validate config file
    my $config_file = shift @ARGV || '';
    (-e $config_file)
        or die $usage;
    # lock config file or die
    open $lockfh, $config_file
        or die "unable to open config file: $config_file: $!";
    flock($lockfh, LOCK_EX|LOCK_NB)
        or exit(2); # unable to lock
    print STDERR "$$: started...\n"; # we have acquired the lock
    my $rc = Config::General->new( $config_file );
    $config = { $rc->getall() };
}

my $programs = Safetynet::Program::Storage::TextFile->new(
    file        => $config->{programs},
);
$programs->reload;

# ---------

my $supervisor = Safetynet::Supervisor->spawn(
    alias           => q{SUPERVISOR},
    binpath         => $config->{binpath},
    programs        => $programs,
);
#if (exists $config->{unix_server}) {
#    Safetynet::UnixServer->spawn(
#        alias       => q{UNIXSERVER},
#        supervisor  => q{MONITOR},
#        %{ $config->{unix_server} },
#    );
#}

$supervisor->yield( 'start_work' );

POE::Kernel->run();

__END__
