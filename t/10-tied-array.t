use strict;
use warnings;

use JavaBin;
use Test::More;
use Tie::Array;

tie my @array, 'Tie::StdArray';

for ( '()', 'qw/foo bar/' ) {
    @array = eval;

    is_deeply from_javabin( to_javabin \@array ), \@array, "tied $_ can round-trip";
}

done_testing;
