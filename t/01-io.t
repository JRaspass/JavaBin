use strict;
use warnings;

use JavaBin;
use Test::Fatal;
use Test::More;

is from_javabin(), undef, 'no args, scalar context';

is_deeply [from_javabin()], [], 'no args, array context';

is exception { from_javabin '' },
    "Invalid JavaBin, insufficient length at $0 line " . (__LINE__ - 1) . ".\n",
    'insufficient length';

is exception { from_javabin "\0\0" },
    "Invalid JavaBin, expected version 2 at $0 line " . (__LINE__ - 1) . ".\n",
    'invalid version';

done_testing;
