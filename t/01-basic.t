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
    # [ 'command', 'param', 'expected_result' ]

    # program management
    [ 'list_programs', undef,                                   { result => [ ] } ],
    [ 'add_program', { 'name' => 'perl-1', 'command' => $^X, }, { result => 1 }  ],
    [ 'list_programs', undef,                                   { result => [ Safetynet::Program->new({ name => 'perl-1', 'command' => $^X })] } ],
    [ 'add_program', { 'name' => 'perl-2', 'command' => $^X, }, { result => 1 }  ],
    [ 'list_programs', undef,                                         
        { result => [ 
                Safetynet::Program->new({ name => 'perl-1', 'command' => $^X }),
                Safetynet::Program->new({ name => 'perl-2', 'command' => $^X }),
            ] } ],
    [ 'add_program', { 'name' => 'perl-2', 'command' => $^X, }, { result => 0 }  ],
    [ 'remove_program', 'perl-1',                               { result => 1 }  ],
    [ 'list_programs', undef,                                   { result => [ Safetynet::Program->new({ name => 'perl-2', 'command' => $^X }), ] } ],
    [ 'info_program', 'perl-2',                                 { result => Safetynet::Program->new({ name => 'perl-2', 'command' => $^X })  } ],
    [ 'info_program', 'perl-1',                                 { result => undef } ],

    # process management
    [ 'info_status', 'perl-2',                                  { result => Safetynet::ProgramStatus->new({ is_running => 0 }) } ],
    [ 'start_program', 'unknown',                               { result => 0 } ], # unknown
    [ 'stop_program', 'perl-2',                                 { result => 0 } ], # not yet started
    [ 'start_program', 'perl-1',                                { result => 0 } ], # deleted a while ago
    [ 'start_program', 'perl-2',                                { result => 1 } ],
    [ 'start_program', 'perl-2',                                { result => 0 } ], # already started
    ##[ 'info_status', 'perl-2',                                  { result => Safetynet::ProgramStatus->new({ is_running => 1 }) } ],
    [ 'stop_program', 'perl-2',                                 { result => 1 } ],
    [ 'stop_program', 'perl-2',                                 { result => 0 } ], # already stopped 
    # more ...
    [ 'add_program', { 'name' => 'perl-3', 'command' => $^X, }, { result => 1 }  ],
    [ 'start_program', 'perl-3',                                { result => 1 } ],
    [ 'remove_program', 'perl-3',                               { result => 0 } ], # running programs cannot be removed
    [ 'stop_program', 'perl-3',                                 { result => 1 } ], # running programs cannot be removed
        
);
my @api_results = ();
my @api_stack   = ();


my $programs = Safetynet::Program::Storage::TextFile->new(
    file => '/tmp/test.programs',
);

my $SUPERVISOR = q{SUPERVISOR};
my $SHELL   = q{SHELL};

my $supervisor = Safetynet::Supervisor->spawn(
    alias       => $SUPERVISOR,
    programs    => $programs,
    binpath     => '/bin:/usr/bin',
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
                my ($cmd, $param, $er) = @$t;
                my $stack = [ $t ];
                push @api_results, $er;
                push @api_stack, $stack;
                $_[KERNEL]->delay( 'timeout' => 30 );
                $supervisor->yield( $cmd, [ $SHELL, 'api_test_result' ], $stack, $param );
                diag "requested $cmd";
            }
            else {
                $_[KERNEL]->yield( 'shutdown' );
            }
        },
        api_test_result => sub {
            $_[KERNEL]->delay( 'timeout' );
            my $stack = $_[ARG0];
            my $t = pop @$stack;
            my $exp_stack = shift @api_stack;
            is_deeply $stack, $exp_stack, 'stack ok';
            my $result = $_[ARG1];
            my $exp_result = shift @api_results;
            is_deeply $result, $exp_result, 'result ok';
            diag Dumper( [ $t, $result ] );
            $_[KERNEL]->yield( 'api_test' );
        },
        timeout => sub {
            fail "operation timeout";
            $_[KERNEL]->yield( 'shutdown' );
        },
        shutdown => sub {
            pass "shutdown";
            $_[KERNEL]->alias_remove( $SHELL );
            $supervisor->yield( 'shutdown' );
        },
    },
);

POE::Kernel->run();


__END__
