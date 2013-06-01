package JavaBin;

use strict;
use warnings;

my ( $bytes, @dispatch, @dispatch_shift, @exts, $tag );

@dispatch = (
    # null
    sub { undef },
    # bool true
    sub { 1 },
    # bool false
    sub { 0 },
    # byte
    sub { unpack 'c', substr $bytes, 0, 1, '' },
    # short
    sub { unpack 's>', substr $bytes, 0, 2, '' },
    # double
    sub { unpack 'd>', substr $bytes, 0, 8, '' },
    # int
    sub { unpack 'i>', substr $bytes, 0, 4, '' },
    # long
    sub { unpack 'q>', substr $bytes, 0, 8, '' },
    # float,
    sub { unpack 'f>', substr $bytes, 0, 4, '' },
    # date
    sub {
        my ( $s, $m, $h, $d, $M, $y ) = gmtime( unpack( 'q>', substr $bytes, 0, 8, '' ) / 1000 );

        sprintf '%d-%02d-%02dT%02d:%02d:%02dZ', $y + 1900, $M + 1, $d, $h, $m, $s;
    },
    # map
    sub { +{ map &{ $dispatch_shift[ ( $tag = ord substr $bytes, 0, 1, '' ) >> 5 ] || $dispatch[$tag] }, 1 .. _vint() * 2 } },
    # solr doc
    sub { &{ $dispatch_shift[ ( $tag = ord substr $bytes, 0, 1, '' ) >> 5 ] || $dispatch[$tag] } },
    # solr doc list
    sub {
        my %result;

        @result{qw/numFound start maxScore docs/} = (
            @{ &{ $dispatch_shift[ ( $tag = ord substr $bytes, 0, 1, '' ) >> 5 ] || $dispatch[$tag] } },
               &{ $dispatch_shift[ ( $tag = ord substr $bytes, 0, 1, '' ) >> 5 ] || $dispatch[$tag] },
        );

        \%result;
    },
    # byte array
    sub { [ unpack 'c*', substr $bytes, 0, _vint(), '' ] },
    # iterator
    sub {
        my @array;

        push @array, &{ $dispatch_shift[ ( $tag = ord substr $bytes, 0, 1, '' ) >> 5 ] || $dispatch[$tag] } until 15 == ord $bytes;

        substr $bytes, 0, 1, '';

        \@array;
    },
);

@dispatch_shift = (
    undef,
    # string
    sub {
        utf8::decode my $string = substr $bytes, 0, read_size(), '';

        $string;
    },
    # small int
    sub { read_small_int() },
    # small long
    sub { read_small_int() },
    # array
    sub { [ map &{ $dispatch_shift[ ( $tag = ord substr $bytes, 0, 1, '' ) >> 5 ] || $dispatch[$tag] }, 1 .. read_size() ] },
    # ordered map
    sub { +{ map &{ $dispatch_shift[ ( $tag = ord substr $bytes, 0, 1, '' ) >> 5 ] || $dispatch[$tag] }, 1 .. read_size() * 2 } },
    # named list
    sub { +{ map &{ $dispatch_shift[ ( $tag = ord substr $bytes, 0, 1, '' ) >> 5 ] || $dispatch[$tag] }, 1 .. read_size() * 2 } },
    # extern string
    sub {
        if ( my $size = read_size() ) {
            $exts[$size - 1];
        }
        else {
            $tag = ord substr $bytes, 0, 1, '';

            utf8::decode my $string = substr $bytes, 0, read_size(), '';

            push @exts, $string;

            $string;
        }
    },
);

sub import {
    no strict 'refs';

    *{ caller() . '::from_javabin' } = \&from_javabin;
}

sub from_javabin {
    $bytes = shift;

    # skip the version byte
    substr $bytes, 0, 1, '';

    @exts = ();

    &{ $dispatch_shift[ ( $tag = ord substr $bytes, 0, 1, '' ) >> 5 ] || $dispatch[$tag] };
}

sub read_size {
    my $size = $tag & 0x1f;

    $size += _vint() if $size == 0x1f;

    $size;
}

sub read_small_int {
    my $result = $tag & 0x0f;

    $result = _vint() << 4 | $result if $tag & 0x10;

    $result;
}

# A prive setter of bytes to allow unit testing.
sub _bytes {
    $bytes = pop;

    shift;
}

# Lucene variable-length +ve integer, the MSB indicates wether you need another octet.
# http://lucene.apache.org/core/old_versioned_docs/versions/3_5_0/fileformats.html#VInt
sub _vint {
    my ( $byte, $shift, $value );

    $value = ( $byte = ord substr $bytes, 0, 1, '' ) & 127;

    $value |= ( ( $byte = ord substr $bytes, 0, 1, '' ) & 127 ) << ( $shift += 7 ) while $byte & 128;

    $value;
}


1;
