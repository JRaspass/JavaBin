package JavaBin;

use strict;
use warnings;

my ( $bytes, @exts, $pos, $tag );

my @dispatch = (
    # null
    sub { undef },
    # bool true
    sub { 1 },
    # bool false
    sub { 0 },
    # byte
    sub { unpack 'c', substr $bytes, $pos++, 1 },
    # short
    sub { unpack 's', reverse substr $bytes, ( $pos += 2 ) - 2, 2 },
    # double
    sub { unpack 'd>', substr $bytes, ( $pos += 8 ) - 8, 8 },
    # int
    sub { unpack 'i', reverse substr $bytes, ( $pos += 4 ) - 4, 4 },
    # long
    sub { unpack 'q', reverse substr $bytes, ( $pos += 8 ) - 8, 8 },
    # float,
    sub { unpack 'f>', substr $bytes, ( $pos += 4 ) - 4, 4 },
    # date
    sub {
        my ( $s, $m, $h, $d, $M, $y ) = gmtime( unpack( 'q', reverse substr $bytes, ( $pos += 8 ) - 8, 8 ) / 1000 );

        sprintf '%d-%02d-%02dT%02d:%02d:%02dZ', $y + 1900, $M + 1, $d, $h, $m, $s;
    },
    # map
    sub { +{ map read_val(), 1 .. read_v_int() * 2 } },
    # solr doc
    sub { read_val() },
    # solr doc list
    sub {
        my %result;

        @result{qw/numFound start maxScore docs/} = ( @{ read_val() }, read_val() );

        \%result;
    },
    # byte array
    sub {
        my $size = read_v_int();

        [ unpack 'c*', substr $bytes, ( $pos += $size ) - $size, $size ];
    },
    # iterator
    sub {
        my ( @array, $byte );

        push @array, read_val() until 15 == ord substr $bytes, $pos, 1;

        $pos++;

        \@array;
    },
);

my @shifted_dispatch = (
    undef,
    # string
    sub {
        my $size = read_size();

        utf8::decode my $string = substr $bytes, $pos, $size;

        $pos += $size;

        $string;
    },
    # small int
    sub { read_small_int() },
    # small long
    sub { read_small_int() },
    # array
    sub { [ map read_val(), 1 .. read_size() ] },
    # ordered map
    sub { +{ map read_val(), 1 .. read_size() * 2 } },
    # named list
    sub { +{ map read_val(), 1 .. read_size() * 2 } },
    # extern string
    sub {
        if ( my $size = read_size() ) {
            $exts[$size - 1];
        }
        else {
            push @exts, my $str = read_val();

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
    $pos = 1;

    @exts = ();

    read_val();
}

sub read_val {
    ( $shifted_dispatch[ ( $tag = ord substr $bytes, $pos++, 1 ) >> 5 ] || $dispatch[$tag] )->();
}

sub read_v_int {
    my $byte = ord substr $bytes, $pos++, 1;

    my $result = $byte & 0x7f;

    my $shift;

    while ( $byte & 0x80 ) {
        $byte = ord substr $bytes, $pos++, 1;

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
