use strict;
use warnings;
use Test::More tests => 24;
use Test::Exception;

BEGIN {
    use_ok 'Safetynet';
    use_ok 'Safetynet::Program::Storage::Memory';
}

my $storage = Safetynet::Program::Storage::Memory->new( );

my ($o, $x);
my $list;

# retrieve all (empty)


$list = $storage->retrieve_all();
is_deeply $list, [ ];

$o = Safetynet::Program->new( name => 'perl', executable => $^X );
ok defined $o;
isa_ok $o, 'Safetynet::Program';
is $o->name, 'perl';
is $o->executable, $^X;

# retrieve all
$list = $storage->retrieve_all();
is_deeply $list, [ ];

# add
ok $storage->add( $o );
dies_ok {
    ok $storage->add( $o );
} 'duplicate';

$list = $storage->retrieve_all();
is_deeply $list, [ Safetynet::Program->new( name => 'perl', executable => $^X ) ];

$o = $storage->retrieve( 'non-existent-name' );
ok not defined $o;

$o = $storage->retrieve( 'perl' );
ok defined $o;
isa_ok $o, 'Safetynet::Program';
is $o->name, 'perl';
is $o->executable, $^X;


# remove
$x = $storage->remove( undef );
is $x, undef;

$list = $storage->retrieve_all(); # check nothing was deleted
is_deeply $list, [ Safetynet::Program->new( name => 'perl', executable => $^X ) ];

$x = $storage->remove( 'non-existent-name-here' );
is $x, undef;

$list = $storage->retrieve_all(); # check nothing was deleted
is_deeply $list, [ Safetynet::Program->new( name => 'perl', executable => $^X ) ];

$x = $storage->remove( 'perl' );
$list = $storage->retrieve_all();
is_deeply $list, [ ], 'remove success';

# add more
{
    $storage->add( Safetynet::Program->new( name => 'echo', executable => '/bin/echo' ) );
    $storage->add( Safetynet::Program->new( name => 'cat', executable => '/bin/cat' ) );

    $list = $storage->retrieve_all();
    is_deeply $list, [ 
        Safetynet::Program->new( name => 'cat', executable => '/bin/cat' ),
        Safetynet::Program->new( name => 'echo', executable => '/bin/echo' ),
    ];
}



lives_ok {
    $storage->commit();
} 'committed';


lives_ok {
    $storage->reload();
} 'reloaded';



__END__
