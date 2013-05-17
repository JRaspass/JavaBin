use JavaBin;
use Test::Deep;
use Test::More;

my $javabin = from_javabin `wget -qO- 'http://localhost:8983/solr/collection1/select?q=*:*&wt=javabin'`;

cmp_deeply $javabin, {
    response => {
        start    => 0,
        numFound => 1,
        docs     => [
            {
                birthday  => '1989-06-07T00:00:00Z',
                id        => 1,
                snowman   => "\N{SNOWMAN}",
                _version_ => re('^\d+$'),
            }
        ],
        maxScore => undef,
    },
    responseHeader => {
        QTime  => re('^\d+$'),
        status => 0,
        params => {
            q  => '*:*',
            wt => 'javabin',
        },
    },
};

done_testing;
