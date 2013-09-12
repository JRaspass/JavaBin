use strict;
use warnings;

use B 'svref_2object';
use JavaBin;
use Test::More 0.96;

sub bnote($) { note "\r\x1b[1m@_\x1b[0m" }
sub nsort(@) { sort { $a <=> $b } @_ }
sub slurp($) { open my $fh, '<', @_ or die $!; local $/; <$fh> }

sub test_ref(@) {
    my ( $type, @values ) = @_;

    my $plural = "${type}s";

    bnote join(' ', split /_/, $type) . 's';

    for (@values) {
        my $ref = from_javabin slurp "${type}-$_";

        subtest $_, sub {
            is_deeply $ref, eval "+$_", 'value matches';

            is svref_2object($ref)->REFCNT, 1, 'reference count is 1';
        };
    }
}

binmode Test::More->builder->$_, ':utf8' for qw/failure_output output todo_output/;

chdir 't/data' or die $!;

bnote 'no args';

is from_javabin(), undef, 'scalar context';
is_deeply [from_javabin()], [], 'array context';

bnote 'constants';

is from_javabin("\0\0"), undef, 'undef';
is from_javabin("\0\1"), 1, 'true';
is from_javabin("\0\2"), 0, 'false';

bnote 'bytes';

is from_javabin(slurp "byte-$_"), $_, "byte $_" for nsort map /-(.*)/, <byte-*>;

bnote 'shorts';

is from_javabin(slurp "short-$_"), $_, "short $_" for nsort map /-(.*)/, <short-*>;

bnote 'ints';

is from_javabin(slurp "int-$_"), $_, "int $_" for nsort map /-(.*)/, <int-*>;

bnote 'longs';

SKIP: {
    my @longs = nsort map /-(.*)/, <long-*>;

    skip '64bit ints are unsupported on your platform.', ~~@longs unless eval { pack 'q' };

    is from_javabin(slurp "long-$_"), $_, "long $_" for @longs;
};

bnote 'floats';

is from_javabin(slurp "float-$_"), $_, "float $_" for sort map /-(.*)/, <float-*>;

bnote 'doubles';

is from_javabin(slurp "double-$_"), $_, "double $_" for sort map /-(.*)/, <double-*>;

bnote 'dates';

is from_javabin(slurp "date-$_"), $_, "date $_" for sort map /-(.*)/, <date-*>;

bnote 'strings';

for ( sort map /-(.*)/, <string-*> ) {
    utf8::decode $_;

    is from_javabin(slurp "string-$_"), $_, qq/string "$_"/;
}

test_ref array              =>         sort map /-(.*)/, <array-*>;
test_ref byte_array         =>         sort map /-(.*)/, <byte_array-*>;
test_ref iterator           =>         sort map /-(.*)/, <iterator-*>;
test_ref map                => reverse sort map /-(.*)/, <map-*>;
test_ref simple_ordered_map =>         sort map /-(.*)/, <simple_ordered_map-*>;
test_ref named_list         =>         sort map /-(.*)/, <named_list-*>;
test_ref solr_document      => reverse sort map /-(.*)/, <solr_document-*>;
test_ref solr_document_list =>         sort map /-(.*)/, <solr_document_list-*>;
test_ref string_caching     =>         sort map /-(.*)/, <string_caching-*>;

bnote 'all';

is_deeply from_javabin(slurp 'all'), {
    array        => [qw/foo bar baz qux/],
    byte         => 127,
    byte_array   => [qw/-128 0 127/],
    byte_neg     => -128,
    iterator     => [qw/qux baz bar foo/],
    false        => 0,
    null         => undef,
    pangram      => 'The quick brown fox jumped over the lazy dog',
    short        =>  32_767,
    short_neg    => -32_768,
    snowman      => "\N{U+2603}",
    true         => 1,
}, 'all';

done_testing;
