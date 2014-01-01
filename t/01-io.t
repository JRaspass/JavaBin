use strict;
use warnings;

use JavaBin;
use Test::Fatal;
use Test::More;

is from_javabin(), undef, 'from_javabin no args, scalar context';

is_deeply [from_javabin()], [], 'from_javabin no args, array context';

my %from = (
     'expected version 2' => "\0\0",
    'insufficient length' => '',
);

is exception { from_javabin $from{$_} },
    "Invalid from_javabin input: $_ at $0 line @{[__LINE__-1]}.\n",
    "from_javabin $_"
        for sort keys %from;

format STDOUT =
.

my %to = (
        'format' => *STDOUT{FORMAT},
          'glob' => *STDOUT,
    'I/O object' => *STDOUT{IO},
       'int ref' => \2,
        'lvalue' => undef,
        'object' => bless( \(my $o) ),
         'regex' => qr//,
    'string ref' => \"",
       'sub ref' => sub {},
);

is exception { to_javabin $to{$_} ? $to{$_} : pos },
    "Invalid to_javabin input: $_ at $0 line @{[__LINE__-1]}.\n",
    "to_javabin $_"
        for sort keys %to;

done_testing;
