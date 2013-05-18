package JavaBin;

use strict;
use warnings;

use constant TERM_OBJ => 'TERMINATE';

my ( $s, $m, $h, $d, $M, $y, @exts, @input, $pos, $string, $tag );

my @dispatch = (
    # null
    sub { undef },
    # bool true
    sub { 1 },
    # bool false
    sub { 0 },
    # byte
    sub { unpack 'c', pack 'C*', $input[$pos++] },
    # short
    sub { unpack 's', pack 'C*', reverse @input[ ( $pos += 2 ) - 2 .. $pos - 1 ] },
    # double
    sub { unpack 'd>', pack 'C*', @input[ ( $pos += 8 ) - 8 .. $pos - 1 ] },
    # int
    sub { unpack 'i', pack 'C*', reverse @input[ ( $pos += 4 ) - 4 .. $pos - 1 ] },
    # long
    sub { unpack 'q', pack 'C*', reverse @input[ ( $pos += 8 ) - 8 .. $pos - 1 ] },
    # float,
    sub { unpack 'f>', pack 'C*', @input[ ( $pos += 4 ) - 4 .. $pos - 1 ] },
    # date
    sub {
        ( $s, $m, $h, $d, $M, $y ) =
            gmtime( unpack( 'q', pack 'C*', reverse @input[ ( $pos += 8 ) - 8 .. $pos - 1 ] ) / 1000 );

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

        [ unpack 'c*', pack 'C*', @input[ ( $pos += $size ) - $size .. $pos - 1 ] ];
    },
    # iterator
    sub {
        my @array;

        while ( 1 ) {
            my $i = read_val();

            last if $i eq TERM_OBJ;

            push @array, $i;
        }

        \@array;
    },
    # term
    sub { TERM_OBJ },
);

my @shifted_dispatch = (
    undef,
    # string
    sub {
        my $size = read_size();

        utf8::decode( $string = pack 'C*', @input[ ( $pos += $size ) - $size .. $pos - 1 ] );

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
            my $str = read_val();

            push @exts, $str;

            $str;
        }
    },
);

sub import {
    no strict 'refs';

    *{ caller() . '::from_javabin' } = \&from_javabin;
}

sub from_javabin {
    @input = unpack 'C*', shift;

    $pos = 1;

    read_val();
}

sub read_val {
    ( $shifted_dispatch[( $tag = $input[$pos++] ) >> 5] || $dispatch[$tag] )->();
}

sub read_v_int {
    my $byte   = $input[$pos++];
    my $result = $byte & 0x7f;
    my $shift  = 7;

    while ( ($byte & 0x80) != 0 ) {
        $byte = $input[$pos++];

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
