use strict;
use warnings;

use JavaBin;
use Test::More 0.96;

binmode Test::More->builder->$_, ':utf8' for qw/failure_output output todo_output/;

for (
    '',
    'perl',
    "\N{U+2603}",
    "Gr\N{U+00FC}\N{U+00DF}en",
    'The quick brown fox jumped over the lazy dog',
) {
    utf8::encode(my $bytes = $_);

    subtest qq/"$bytes"/, sub {
        my $expected = "\2";
        my $len = length $bytes;

        if ( $len < 31 ) {
            $expected .= chr( 32 | $len );
        }
        else {
            $expected .= chr( 32 | 31 ) . chr $len - 31;
        }

        $expected .= $bytes;

        is my $got = to_javabin($_), $expected, 'to_javabin';

        is from_javabin($got), $_, 'from_javabin';
    };
}

done_testing;