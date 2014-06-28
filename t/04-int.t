use strict;
use warnings;

use B qw/svref_2object SVf_IOK SVf_NOK SVf_POK/;
use Config;
use JavaBin;
use Test::More;

my @packs = qw/- - - c s> - l> q>/;

for (
    [ -9_223_372_036_854_775_808, 7 ], #  QUAD_MIN
    [ -9_223_372_036_854_775_807, 7 ], #  QUAD_MIN + 1
    [             -2_147_483_649, 7 ], #  LONG_MIN - 1
    [             -2_147_483_648, 6 ], #  LONG_MIN
    [             -2_147_483_647, 6 ], #  LONG_MIN + 1
    [                    -32_769, 6 ], # SHORT_MIN - 1
    [                    -32_768, 4 ], # SHORT_MIN
    [                    -32_767, 4 ], # SHORT_MIN + 1
    [                       -129, 4 ], #  CHAR_MIN - 1
    [                       -128, 3 ], #  CHAR_MIN
    [                       -127, 3 ], #  CHAR_MIN + 1
    [                         -1, 3 ],
    [                          0, 3 ],
    [                          1, 3 ],
    [                        126, 3 ], #  CHAR_MAX - 1
    [                        127, 3 ], #  CHAR_MAX
    [                        128, 4 ], #  CHAR_MAX + 1
    [                     32_766, 4 ], # SHORT_MAX - 1
    [                     32_767, 4 ], # SHORT_MAX
    [                     32_768, 6 ], # SHORT_MAX + 1
    [              2_147_483_646, 6 ], #  LONG_MAX - 1
    [              2_147_483_647, 6 ], #  LONG_MAX
    [              2_147_483_648, 7 ], #  LONG_MAX + 1
    [  9_223_372_036_854_775_806, 7 ], #  QUAD_MAX - 1
    [  9_223_372_036_854_775_807, 7 ], #  QUAD_MAX
){
    my ( $pv, $size ) = @$_;

    next if $size == 7 && !$Config{use64bitint};

    my $iv = eval $pv; # Stringify $pv to a PVIV, create a new IV in $iv.

    my $flags = svref_2object(\$iv)->FLAGS;

    ok $flags & SVf_IOK, "$pv is IOK";
    ok !($flags & SVf_NOK), "$pv isn't NOK";
    ok !($flags & SVf_POK), "$pv isn't POK";

    my $javabin = "\2" . chr($size) . pack $packs[$size], $iv;

    is to_javabin($iv), $javabin, "$pv to_javabin";

    is from_javabin($javabin), $iv, "$pv from_javabin";

    $javabin = "\2" . chr( 32 | length $pv ) . $pv;

    $flags = svref_2object(\$pv)->FLAGS;

    ok $flags & SVf_IOK, qq/"$pv" is IOK/;
    ok !($flags & SVf_NOK), qq/"$pv" isn't NOK/;
    ok $flags & SVf_POK, qq/"$pv" is POK/;

    is to_javabin($pv), $javabin, qq/"$pv" to_javabin/;

    is from_javabin($javabin), $iv, qq/"$pv" from_javabin/;
}

done_testing;
