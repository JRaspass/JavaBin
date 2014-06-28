# Test that UTF-8 hash keys work.

use strict;
use utf8;
use warnings;

use JavaBin;
use Test::More;

binmode Test::More->builder->$_, ':encoding(UTF-8)' for qw/failure_output output/;

# Make an array of alphabets, which each one including a diff greek letter.
my $letters = join '', 'a'..'z';

my @letters;

substr $letters[$_] = $letters, $_, 1, chr( $_ + 945 ) for 0..25;

for (@letters) {
    my $hash = from_javabin to_javabin { $_ => undef };

    ok exists $hash->{$_}, "\$hash->{$_} exists?";
}

done_testing;
