use strict;
use warnings;
use Test::More qw/no_plan/;
use Data::Dumper;

BEGIN {
    use_ok 'Safetynet';
    use_ok 'Safetynet::Program::Storage::Memory';
    use_ok 'POE::Kernel';
    use_ok 'POE::Session';
}

my $programs = Safetynet::Program::Storage::Memory->new();

my $MONITOR = q{MONITOR};
my $SHELL   = q{SHELL};

my $monitor =Safetynet::Monitor->spawn(
    alias       => $MONITOR,
    programs    => $programs,
);

# shell
POE::Session->create(
    inline_states => {
        _start => sub {
            $_[KERNEL]->alias_set( $SHELL );
            $_[KERNEL]->delay( 'timeout' => 10 );
            $monitor->yield( 'program_list', [ $SHELL, 'monitor_program_list_result' ], [ 1, 2 ] );
        },
        monitor_program_list_result => sub {
            $_[KERNEL]->delay( 'timeout' );
            my $stack = $_[ARG0];
            is_deeply $stack, [ 1, 2 ], 'stack ok';
            my $list = $_[ARG1];
            isa_ok $list, 'ARRAY';
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
