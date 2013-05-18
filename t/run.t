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
                birthday  => '1989-06-07T00:00:00Z',
                id        => 1,
                snowman   => "\N{SNOWMAN}",
                _version_ => 457917000211,
            },
        ],
        maxScore => undef,
    },
    responseHeader => {
        QTime  => 7,
        status => 0,
        params => {
            q  => '*:*',
            wt => 'javabin',
        },
    },
};

done_testing;
