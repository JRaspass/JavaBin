use strict;
use warnings;

use JavaBin;
use Test::Fatal;
use Test::More;

is from_javabin(), undef, 'no args, scalar context';

is_deeply [from_javabin()], [], 'no args, array context';

is exception { from_javabin '' },
    "Invalid from_javabin input: insufficient length at $0 line " . (__LINE__ - 1) . ".\n",
    'insufficient length';

is exception { from_javabin "\0\0" },
    "Invalid from_javabin input: expected version 2 at $0 line " . (__LINE__ - 1) . ".\n",
    'invalid version';

is exception { to_javabin \"" },
    "Invalid to_javabin input: string ref at $0 line " . (__LINE__ - 1) . ".\n",
    'to_javabin \""';

is exception { to_javabin qr// },
    "Invalid to_javabin input: regex at $0 line " . (__LINE__ - 1) . ".\n",
    'to_javabin qr//';

is exception { no warnings 'once'; to_javabin *DATA },
    "Invalid to_javabin input: glob at $0 line " . (__LINE__ - 1) . ".\n",
    'to_javabin *DATA';

is exception { to_javabin sub {} },
    "Invalid to_javabin input: sub ref at $0 line " . (__LINE__ - 1) . ".\n",
    'to_javabin sub {}';

done_testing;
