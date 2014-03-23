package JavaBin 0.8;

use strict;
use warnings;

use XSLoader;

XSLoader::load();

sub import {
    shift;

    my $pkg = caller . '::';

    no strict 'refs';

    *{ $pkg . $_ } = \&$_ for @_ ? @_ : qw/from_javabin to_javabin/;
}

1;
