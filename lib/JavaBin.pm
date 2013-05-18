package JavaBin;

use v5.10;

use strict;
use warnings;

use constant NULL       => 0;
use constant BOOL_TRUE  => 1;
use constant BOOL_FALSE => 2;
use constant BYTE       => 3;
use constant SHORT      => 4;
use constant DOUBLE     => 5;
use constant INT        => 6;
use constant LONG       => 7;
use constant FLOAT      => 8;
use constant DATE       => 9;
use constant MAP        => 10;
use constant SOLRDOC    => 11;
use constant SOLRDOCLST => 12;
use constant BYTEARR    => 13;
use constant ITERATOR   => 14;
use constant TERM       => 15;

use constant SHIFTED_STR           => 1;
use constant SHIFTED_SINT          => 2;
use constant SHIFTED_SLONG         => 3;
use constant SHIFTED_ARR           => 4;
use constant SHIFTED_ORDERED_MAP   => 5;
use constant SHIFTED_NAMED_LST     => 6;
use constant SHIFTED_EXTERN_STRING => 7;

use constant TERM_OBJ => 'TERMINATE';

my ( $s, $m, $h, $d, $M, $y, @exts, @input, $pos, $tag );

sub import {
    no strict 'refs';

    *{ caller() . '::from_javabin' } = \&from_javabin;
}

sub from_javabin {
    @input = unpack 'C*', shift;
    $pos = 1;

    return read_val();
}

sub get_byte {
    return $input[ $pos++ ];
}

sub get_bytes {
    #return @input[ $pos .. ( ( $pos += shift ) -1 ) ];
    my @ret = @input[ $pos .. ( $pos + $_[0] - 1 )];
    $pos += $_[0];
    return @ret;
}

sub read_val {
    $tag = get_byte();

    given ( $tag >> 5 ) {
        when ( SHIFTED_STR ) {
            my $bytes = pack 'C*', get_bytes( read_size() );

            utf8::decode $bytes;

            return $bytes;
        }
        when ( SHIFTED_ARR ) {
            return [ map read_val(), 1..read_size() ];
        }
        when ( SHIFTED_EXTERN_STRING ) {
            if ( my $size = read_size() ) {
                return $exts[$size - 1];
            }
            else {
                my $str = read_val();
                push @exts, $str;
                return $str;
            }
        }
        when ( SHIFTED_ORDERED_MAP || SHIFTED_NAMED_LST ) {
            return { map read_val(), 1 .. read_size() * 2 };
        }
        when ( SHIFTED_SINT ) {
            return read_small_int();
        }
        when ( SHIFTED_SLONG ) {
            return read_small_int();
        }
    }

    given ( $tag ) {
        when ( NULL ) {
            return undef;
        }
        when ( BOOL_TRUE ) {
            return 1;
        }
        when ( BOOL_FALSE ) {
            return 0;
        }
        when ( BYTE ) {
            return unpack 'c', pack 'C*', get_byte();
        }
        when ( SHORT ) {
            return unpack 's', pack 'C*', reverse get_bytes(2);
        }
        when ( DOUBLE ) {
            return unpack 'd>', pack 'C*', get_bytes(8);
        }
        when ( INT ) {
            return unpack 'i', pack 'C*', reverse get_bytes(4);
        }
        when ( LONG ) {
            return unpack 'q', pack 'C*', reverse get_bytes(8);
        }
        when ( FLOAT ) {
            return unpack 'f>', pack 'C*', get_bytes(4);
        }
        when ( DATE ) {
            ( $s, $m, $h, $d, $M, $y ) = gmtime(
                unpack( 'q', pack 'C*', reverse get_bytes(8) ) / 1000
            );

            return sprintf '%d-%02d-%02dT%02d:%02d:%02dZ', $y + 1900, $M + 1, $d, $h, $m, $s;
        }
        when ( MAP ) {
            return { map read_val(), 1 .. read_v_int() * 2 };
        }
        when ( BYTEARR ) {
            return [ unpack 'c*', pack 'C*', get_bytes(read_v_int()) ];
        }
        when ( ITERATOR ) {
            my @array;
            while ( 1 ) {
                my $i = read_val();
                last if $i eq TERM_OBJ;
                push @array, $i;
            }
            return \@array;
        }
        when ( TERM ) {
            return TERM_OBJ;
        }
        when ( SOLRDOC ) {
            return read_val();
        }
        when ( SOLRDOCLST ) {
            my %result;

            @result{qw/numFound start maxScore docs/} =
                ( @{ read_val() }, read_val() );

            return \%result;
        }
    }
}

sub read_v_int {
    my $byte = get_byte();
    my $result = $byte & 0x7f;
    my $shift = 7;
    while ( ($byte & 0x80) != 0 ) {
        $byte = get_byte();
        $result |= (($byte & 0x7f) << $shift);
        $shift += 7;
    }
    return $result;
}

sub read_size {
    my $size = $tag & 0x1f;
    $size += read_v_int() if $size == 0x1f;
    return $size;
}

sub read_small_int {
    my $result = $tag & 0x0F;
    $result = ((read_v_int() << 4) | $result) if $tag & 0x10;
    return $result;
}

1;
