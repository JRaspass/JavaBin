use strict;
use warnings;

use charnames ':full';

use JavaBin;
use Test::More;

note 'constants';

is from_javabin "\0\0", undef, 'undef';
is from_javabin "\0\1", 1, 'true';
is from_javabin "\0\2", 0, 'false';

note 'bytes';

is from_javabin( "\0\3" . pack 'c', $_ ), $_, "byte $_" for qw/-128
                                                                0
                                                                127/;

note 'shorts';

is from_javabin( "\0\4" . pack 's>', $_ ), $_, "short $_" for qw/-32768
                                                                 -129
                                                                  0
                                                                  128
                                                                  32767/;

note 'ints';

is from_javabin( "\0\6" . pack 'l>', $_ ), $_, "int $_" for qw/-2147483648
                                                               -8388609
                                                               -32769
                                                               -129
                                                                0
                                                                128
                                                                32768
                                                                8388608
                                                                2147483647/;

note 'longs';

SKIP: {
    skip '64bit ints are unsupported on your platform.', 1 unless eval { pack 'q' };

    is from_javabin( "\0\7" . pack 'q>', $_ ), $_, "long $_" for qw/-9223372036854775808
                                                                    -36028797018963969
                                                                    -140737488355329
                                                                    -549755813889
                                                                    -2147483649
                                                                    -8388609
                                                                    -32769
                                                                    -129
                                                                     0
                                                                     128
                                                                     32768
                                                                     8388608
                                                                     2147483648
                                                                     549755813888
                                                                     140737488355328
                                                                     36028797018963968
                                                                     9223372036854775807/;
};

note 'vints';

my %vints = (
    127    => [ 0x7F ],
    128    => [ 0x80, 0x01 ],
    16_383 => [ 0xFF, 0x7F ],
    16_384 => [ 0x80, 0x80, 0x01 ],
);

is( JavaBin->_bytes( pack 'C*', @{ $vints{$_} } )->_vint, $_, "vint $_" ) for sort keys %vints;

note 'all';

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
    null         => undef,
    pangram      => 'The quick brown fox jumped over the lazy dog',
    short        =>  32_767,
    short_neg    => -32_768,
    snowman      => "\N{SNOWMAN}",
    true         => 1,
}, 'from_javabin';

done_testing;
