use strict;
use warnings;
use Test::More qw/no_plan/;
use Data::Dumper;

BEGIN {
    use_ok 'Safetynet';
    use_ok 'Safetynet::Program::Storage::TextFile';
    use_ok 'Safetynet::Shell::Basic';
    use_ok 'POE::Kernel';
    use_ok 'POE::Session';
}


my $programs = Safetynet::Program::Storage::Memory->new();

my $MONITOR = q{MONITOR};
my $SHELL   = q{SHELL};
my $SHELLSESS = q{SHELLSESSION};

my $monitor = Safetynet::Monitor->spawn(
    alias       => $MONITOR,
    programs    => $programs,
    binpath     => '/bin:/usr/bin',
);

my $shell = Safetynet::Shell::Basic->spawn(
    alias       => $SHELL,
    monitor     => $monitor,
);

# server session 

POE::Session->create(
    inline_states => {
        _start => sub {
            $_[KERNEL]->alias_set( $SHELLSESS );
            $_[KERNEL]->yield( 'shell_test' );
        },
        shell_test => sub {
            $_[KERNEL]->delay( 'timeout' => 5 );
            $shell->yield( 'session_input' => [ $SHELLSESS, 'shell_test_result' ], [ ], 'view-all' );
        },
        shell_test_result => sub {
            $_[KERNEL]->delay( 'timeout' );
            my $stack = $_[ARG0];
            my $output = $_[ARG1];
            diag 'output: '.$output;
            pass 'result ok';
            $_[KERNEL]->yield( 'shutdown' );
        },
        timeout => sub {
            fail "operation timeout";
            $_[KERNEL]->yield( 'shutdown' );
        },
        shutdown => sub {
            pass "shutdown";
            $_[KERNEL]->alias_remove( $SHELL );
            $monitor->yield( 'shutdown' );
        },
    },
);

POE::Kernel->run();


__END__

