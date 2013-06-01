use strict;
use warnings;

use charnames ':full';

use JavaBin;
use Test::More;

my %vints = (
    127    => [ 0x7F ],
    128    => [ 0x80, 0x01 ],
    16_383 => [ 0xFF, 0x7F ],
    16_384 => [ 0x80, 0x80, 0x01 ],
);

is( JavaBin->_bytes( pack 'C*', @{ $vints{$_} } )->_vint, $_, "_vint $_" ) for sort keys %vints;

open my $fh, '<', 't/data';

is_deeply from_javabin( do { local $/; <$fh> } ), {
    array        => [qw/foo bar baz qux/],
    byte         => 127,
    byte_array   => [qw/-128 0 127/],
    byte_neg     => -128,
    date         => '1989-06-07T00:00:00Z',
    double       => 1.797_693_134_862_31e308,
    iterator     => [qw/qux baz bar foo/],
    false        => 0,
    float        => 3.402_823_466_385_29e38,
    shifted_sint => 2_147_483_647,
    long         => 9_223_372_036_854_775_807,
    long_neg     => -9_223_372_036_854_775_808,
    null         => undef,
    short        => 32_767,
    short_neg    => -32_768,
    snowman      => "\N{SNOWMAN}",
    true         => 1,
}, 'from_javabin';

done_testing;
