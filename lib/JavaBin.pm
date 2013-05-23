package JavaBin;

use strict;
use warnings;

my ( @exts, $fh, $tag );

my @dispatch = (
    # null
    sub { undef },
    # bool true
    sub { 1 },
    # bool false
    sub { 0 },
    # byte
    sub {
        read $fh, my $byte, 1;

        unpack 'c', $byte;
    },
    # short
    sub {
        read $fh, my $bytes, 2;

        unpack 's', reverse $bytes;
    },
    # double
    sub {
        read $fh, my $bytes, 8;

        unpack 'd>', $bytes;
    },
    # int
    sub {
        read $fh, my $bytes, 4;

        unpack 'i', reverse $bytes;
    },
    # long
    sub {
        read $fh, my $bytes, 8;

        unpack 'q', reverse $bytes;
    },
    # float,
    sub {
        read $fh, my $bytes, 4;

        unpack 'f>', $bytes;
    },
    # date
    sub {
        read $fh, my $bytes, 8;

        my ( $s, $m, $h, $d, $M, $y ) = gmtime( unpack( 'q', reverse $bytes ) / 1000 );

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
        read $fh, my $bytes, read_v_int();

        [ unpack 'c*', $bytes ];
    },
    # iterator
    sub {
        my ( @array, $byte );

        push @array, read_val()
            while read $fh, $byte, 1 and 15 != unpack 'C', $byte and seek $fh, -1, 1;

        \@array;
    },
);

my @shifted_dispatch = (
    undef,
    # string
    sub {
        read $fh, my $bytes, read_size();

        utf8::decode $bytes;

        $bytes;
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
    open $fh, '<', \shift;

    # skip the version byte
    seek $fh, 1, 0;

    @exts = ();

    read_val();
}

sub read_val {
    read $fh, my $byte, 1;

    ( $shifted_dispatch[ ( $tag = unpack 'C', $byte ) >> 5 ] || $dispatch[$tag] )->();
}

sub read_v_int {
    read $fh, my $byte, 1;

    $byte = unpack 'C', $byte;

    my $result = $byte & 0x7f;

    my $shift = 7;

    while ( ($byte & 0x80) != 0 ) {
        read $fh, $byte, 1;

        $byte = unpack 'C', $byte;

        $result |= (($byte & 0x7f) << $shift);

        $shift += 7;
    }

    $result;
}

sub read_size {
    my $size = $tag & 0x1f;

    $size += read_v_int() if $size == 0x1f;

    $size;
}

sub read_small_int {
    my $result = $tag & 0x0F;

    $result = ((read_v_int() << 4) | $result) if $tag & 0x10;

    $result;
}

1;
