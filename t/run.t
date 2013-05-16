use JavaBin;
use Test::More;

my $javabin = `wget -qO- 'http://localhost:8983/solr/collection1/select?q=*:*&wt=javabin'`;

is_deeply from_javabin($javabin), {
    response => {
        start    => 0,
        numFound => 0,
        docs     => [],
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

is 1,1;

done_testing;
