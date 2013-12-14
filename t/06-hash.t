use strict;
use warnings;

use JavaBin;
use Test::More;

my @tests = (
    '{}'               => "\2\12\0",
    '{ foo => "bar" }' => "\2\12\1\0\43\146\157\157\43\142\141\162",
    '{ foo => {} }'    => "\2\12\1\0\43\146\157\157\12\0",
);

for ( my $i = 0; $i < @tests; $i += 2 ) {
    my ( $name, $bin ) = @tests[$i, $i + 1];

    my $ref = eval $name;

    is to_javabin($ref), $bin, "  to_javabin $name";

    is_deeply from_javabin($bin), $ref, "from_javabin $name";
}

done_testing;
