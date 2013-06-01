package JavaBin;

use strict;
use warnings;

my ( $bytes, @dispatch, @dispatch_shift, @exts, $size, $tag );

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
    sub {
        +{
            map
                &{ $dispatch_shift[ ( $tag = ord substr $bytes, 0, 1, '' ) >> 5 ] || $dispatch[$tag] },
                1 .. _vint() * 2
        }
    },
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

        push @array, &{ $dispatch_shift[ $tag >> 5 ] || $dispatch[$tag] }
            until ( $tag = ord substr $bytes, 0, 1, '' ) == 15;

        \@array;
    },
);

# These datatypes are matched by taking the tag byte, shifting it by 5 so to only read
# the first 3 bits of the tag byte, giving it a range or 0-7 inclusive.
#
# The remaining 5 bits can then be used to store the size of the datatype, e.g. how
# many chars in a string, this therefore has a range of 0-31, if the size exceeds or
# matches this then an additional vint is added.
#
# The overview of the tag byte is therefore TTTSSSSS with T and S being type and size.
@dispatch_shift = (
    undef,
    # string
    sub {
        utf8::decode my $string = substr $bytes, 0, ( $size = $tag & 31 ) == 31 ? 31 + _vint() : $size, '';

        $string;
    },
    # small int
    sub { read_small_int() },
    # small long
    sub { read_small_int() },
    # array
    sub {
        [
            map
                &{ $dispatch_shift[ ( $tag = ord substr $bytes, 0, 1, '' ) >> 5 ] || $dispatch[$tag] },
                1 .. ( ( $size = $tag & 31 ) == 31 ? 31 + _vint() : $size )
        ]
    },
    # ordered map
    sub {
        +{
            map
                &{ $dispatch_shift[ ( $tag = ord substr $bytes, 0, 1, '' ) >> 5 ] || $dispatch[$tag] },
                1 .. ( ( $size = $tag & 31 ) == 31 ? 31 + _vint() : $size ) * 2
        }
    },
    # named list
    sub {
        +{
            map
                &{ $dispatch_shift[ ( $tag = ord substr $bytes, 0, 1, '' ) >> 5 ] || $dispatch[$tag] },
                1 .. ( ( $size = $tag & 31 ) == 31 ? 31 + _vint() : $size ) * 2
        }
    },
    # extern string
    sub {
        if ( ( $size = $tag & 31 ) == 31 ? $size += _vint() : $size ) {
            $exts[$size - 1];
        }
        else {
            utf8::decode my $string =
                substr $bytes, 0, ( $size = ord( substr $bytes, 0, 1, '' ) & 31 ) == 31 ? 31 + _vint() : $size, '';

            push @exts, $string;

            $string;
        }
    },
);

sub from_javabin {
    # skip the version byte
    $bytes = substr shift, 1;

    @exts = ();

    &{ $dispatch_shift[ ( $tag = ord substr $bytes, 0, 1, '' ) >> 5 ] || $dispatch[$tag] };
}

sub import {
    no strict 'refs';

    *{ caller() . '::from_javabin' } = \&from_javabin;
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

# Lucene variable-length +ve integer, the MSB indicates whether you need another octet.
# http://lucene.apache.org/core/old_versioned_docs/versions/3_5_0/fileformats.html#VInt
sub _vint {
    my ( $byte, $shift, $value );

    $value = ( $byte = ord substr $bytes, 0, 1, '' ) & 127;

    $value |= ( ( $byte = ord substr $bytes, 0, 1, '' ) & 127 ) << ( $shift += 7 ) while $byte & 128;

    $value;
}


1;
