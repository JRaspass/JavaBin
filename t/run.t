use strict;
use warnings;

use charnames ':full';

use JavaBin;
use Test::More;

open my $fh, '<', 't/data';

is_deeply from_javabin( do { local $/; <$fh> } ), {
    response => {
        start    => 0,
        numFound => 1,
        docs     => [
            {
                birthday       => '1989-06-07T00:00:00Z',
                false          => 0,
                id             => 1,
                metasyntactics => [qw/foo bar baz qux/],
                snowman        => "\N{SNOWMAN}",
                true           => 1,
                _version_      => 124134326922003,
            },
        ],
        maxScore => undef,
    },
    responseHeader => {
        QTime  => 0,
        status => 0,
        params => {
            q  => '*:*',
            wt => 'javabin',
        },
    },
};

done_testing;
