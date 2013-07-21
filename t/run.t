use strict;
use warnings;

use charnames ':full';

use JavaBin;
use Test::More;

sub slurp($) { open my $fh, '<', @_ or die $!; local $/; <$fh> }

chdir 't/data' or die $!;

note 'constants';

is from_javabin "\0\0", undef, 'undef';
is from_javabin "\0\1", 1, 'true';
is from_javabin "\0\2", 0, 'false';

note 'bytes';

is from_javabin(slurp "byte-$_"), $_, "byte $_" for sort { $a <=> $b } map /byte-(.*)/, <byte-*>;

note 'shorts';

for ( sort { $a <=> $b } map /short-(.*)/, <short-*> ) {
    note $_;

    my $bin = slurp "short-$_";

    note map "$_\n", unpack('B*', $bin) =~ /\d{8}/g;

    my $result = from_javabin $bin;

    is $result, $_, "short $_";
}

done_testing;
exit;

note 'ints';

is from_javabin(slurp "int-$_"), $_, "int $_" for sort { $a <=> $b } map /int-(.*)/, <int-*>;

note 'longs';

SKIP: {
    skip '64bit ints are unsupported on your platform.', 1 unless eval { pack 'q' };

    is from_javabin(slurp "long-$_"), $_, "long $_" for sort { $a <=> $b } map /long-(.*)/, <long-*>;
};

note 'dates';

/date-(.*)/ && is from_javabin(slurp $_), $1, "date $1" for <date-*>;

#note 'all';

#is_deeply from_javabin(slurp 'all'), {
#    array        => [qw/foo bar baz qux/],
#    byte         => 127,
#    byte_array   => [qw/-128 0 127/],
#    byte_neg     => -128,
#    double       => 1.797_693_134_862_31e308,
#    iterator     => [qw/qux baz bar foo/],
#    false        => 0,
#    float        => 3.402_823_466_385_29e38,
#    shifted_sint => 2_147_483_647,
#    null         => undef,
#    pangram      => 'The quick brown fox jumped over the lazy dog',
#    short        =>  32_767,
#    short_neg    => -32_768,
#    snowman      => "\N{SNOWMAN}",
#    true         => 1,
#}, 'all';

done_testing;
