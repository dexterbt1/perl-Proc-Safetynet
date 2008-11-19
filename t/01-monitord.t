use strict;
use warnings;
use Test::More qw/no_plan/;
use Data::Dumper;

BEGIN {
    use_ok 'Safetynet';
    use_ok 'Safetynet::Program::Storage::TextFile';
    use_ok 'POE::Kernel';
    use_ok 'POE::Session';
}

my @api_tests = (
    # [ 'namespace', 'command', 'param', 'expected_result' ]
    [ 'program', 'unknown-command-here', undef,                         { 'error' => 'unknown command' } ],
    [ 'program', 'list', undef,                                         { result => [ ] } ],
    [ 'program', 'add', { 'name' => 'perl-1', 'command' => $^X, },      { 'result' => 1 }  ],
    [ 'program', 'list', undef,                                         
        { result => [ Safetynet::Program->new({ name => 'perl-1', 'command' => $^X })] } ],
    [ 'program', 'add', { 'name' => 'perl-2', 'command' => $^X, },      { 'result' => 1 }  ],
    [ 'program', 'list', undef,                                         
        { result => [ 
                Safetynet::Program->new({ name => 'perl-1', 'command' => $^X }),
                Safetynet::Program->new({ name => 'perl-2', 'command' => $^X }),
            ] } ],
    [ 'program', 'add', { 'name' => 'perl-2', 'command' => $^X, },      { 'result' => 0 }  ],
    [ 'program', 'remove', 'perl-1',   { 'result' => 1 }  ],
    [ 'program', 'list', undef,                                         
        { result => [ 
                Safetynet::Program->new({ name => 'perl-2', 'command' => $^X }),
            ] } ],
    [ 'program', 'settings', 'perl-2', 
        { result => Safetynet::Program->new({ name => 'perl-2', 'command' => $^X })  } ],
    [ 'program', 'settings', 'perl-1', 
        { result => undef } ],
);
my @api_results = ();
my @api_stack   = ();


my $programs = Safetynet::Program::Storage::TextFile->new(
    file => '/tmp/test.programs',
);

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
            $_[KERNEL]->yield( 'api_test' );
        },
        api_test => sub {
            my $t = shift @api_tests;
            if (defined $t) {
                my ($ns, $cmd, $param, $er) = @$t;
                my $stack = [ $t ];
                push @api_results, $er;
                push @api_stack, $stack;
                $_[KERNEL]->delay( 'timeout' => 30 );
                $monitor->yield( $ns, [ $SHELL, 'api_test_result' ], $stack, $cmd, $param );
            }
            else {
                $_[KERNEL]->yield( 'shutdown' );
            }
        },
        api_test_result => sub {
            $_[KERNEL]->delay( 'timeout' );
            my $stack = $_[ARG0];
            my $exp_stack = shift @api_stack;
            is_deeply $stack, $exp_stack, 'stack ok';
            my $result = $_[ARG1];
            my $exp_result = shift @api_results;
            is_deeply $result, $exp_result, 'result ok';
            diag Dumper( $result );
            $_[KERNEL]->yield( 'api_test' );
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
