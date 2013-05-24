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
    sub { +{ map &{ $dispatch_shift[ ( $tag = ord substr $bytes, 0, 1, '' ) >> 5 ] || $dispatch[$tag] }, 1 .. read_v_int() * 2 } },
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
    sub { [ unpack 'c*', substr $bytes, 0, read_v_int(), '' ] },
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
            push @exts, my $str = &{ $dispatch_shift[ ( $tag = ord substr $bytes, 0, 1, '' ) >> 5 ] || $dispatch[$tag] };

            $str;
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

sub read_v_int {
    my $byte = ord substr $bytes, 0, 1, '';

    my $result = $byte & 0x7f;

    my $shift;

    while ( $byte & 0x80 ) {
        $byte = ord substr $bytes, 0, 1, '';

        $result |= ( $byte & 0x7f ) << ( $shift += 7 );
    }

    $result;
}

sub read_size {
    my $size = $tag & 0x1f;

    $size += read_v_int() if $size == 0x1f;

    $size;
}

sub read_small_int {
    my $result = $tag & 0x0f;

    $result = read_v_int() << 4 | $result if $tag & 0x10;

    $result;
}

1;
