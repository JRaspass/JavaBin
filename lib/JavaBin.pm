package JavaBin;

use strict;
use warnings;

use Filter::cpp;

# define BYTES($num) substr $bytes, 0, $num, ''
# define DISPATCH &{ $dispatch_shift[ ( $tag = ord BYTES(1) ) >> 5 ] || $dispatch[$tag] }

my ( $bytes, @dispatch, @dispatch_shift, @exts, $size, $tag );

@dispatch = (
    # null
    sub { undef },
    # bool true
    sub { 1 },
    # bool false
    sub { 0 },
    # byte
    sub { unpack 'c', BYTES(1) },
    # short
    sub { unpack 's>', BYTES(2) },
    # double
    sub { unpack 'd>', BYTES(8) },
    # int
    sub { unpack 'l>', BYTES(4) },
    # long
    sub { unpack 'q>', BYTES(8) },
    # float,
    sub { unpack 'f>', BYTES(4) },
    # date
    sub {
        my ( $s, $m, $h, $d, $M, $y ) = gmtime( unpack( 'q>', BYTES(8) ) / 1000 );

        sprintf '%d-%02d-%02dT%02d:%02d:%02dZ', $y + 1900, $M + 1, $d, $h, $m, $s;
    },
    # map
    sub { +{ map DISPATCH, 1 .. _vint() * 2 } },
    # solr doc
    sub { DISPATCH },
    # solr doc list
    sub {
        my %result;

        @result{qw/numFound start maxScore docs/} = ( @{ DISPATCH }, DISPATCH );

        \%result;
    },
    # byte array
    sub { [ unpack 'c*', BYTES(_vint()) ] },
    # iterator
    sub {
        my @array;

        push @array, &{ $dispatch_shift[ $tag >> 5 ] || $dispatch[$tag] }
            until ( $tag = ord BYTES(1) ) == 15;

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
        utf8::decode my $string = BYTES( ( $size = $tag & 31 ) == 31 ? 31 + _vint() : $size );

        $string;
    },
    # small int
    sub { read_small_int() },
    # small long
    sub { read_small_int() },
    # array
    sub { [ map DISPATCH, 1 .. ( ( $size = $tag & 31 ) == 31 ? 31 + _vint() : $size ) ] },
    # ordered map
    sub { +{ map DISPATCH, 1 .. ( ( $size = $tag & 31 ) == 31 ? 31 + _vint() : $size ) * 2 } },
    # named list
    sub { +{ map DISPATCH, 1 .. ( ( $size = $tag & 31 ) == 31 ? 31 + _vint() : $size ) * 2 } },
    # extern string
    sub {
        if ( ( $size = $tag & 31 ) == 31 ? $size += _vint() : $size ) {
            $exts[$size - 1];
        }
        else {
            utf8::decode my $string = BYTES( ( $size = ord( BYTES(1) ) & 31 ) == 31 ? 31 + _vint() : $size );

            push @exts, $string;

            $string;
        }
    },
);

sub from_javabin($) {
    # Read the input into $bytes whilst skipping the version byte.
    $bytes = substr shift, 1;

    @exts = ();

    DISPATCH;
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

# A private setter of bytes to allow unit testing.
sub _bytes {
    $bytes = pop;

    shift;
}

# Lucene variable-length +ve integer, the MSB indicates whether you need another octet.
# http://lucene.apache.org/core/old_versioned_docs/versions/3_5_0/fileformats.html#VInt
sub _vint {
    my ( $byte, $shift, $value );

    $value = ( $byte = ord BYTES(1) ) & 127;

    $value |= ( ( $byte = ord BYTES(1) ) & 127 ) << ( $shift += 7 ) while $byte & 128;

    $value;
}

1;

=head1 NAME

JavaBin - Apache Solr JavaBin (de)serializer

=head1 SYNOPSIS

 use JavaBin;

 my $result = from_javabin $binary_data;

=head1 DESCRIPTION

JavaBin is a compact binary format used by L<Apache Solr|http://lucene.apache.org/solr>.

For more information on this format see the L<Solr Wiki|http://wiki.apache.org/solr/javabin>.

This package provides a deserializer for this format, with a serializer planned.

=head1 FUNCTIONS

=head2 from_javabin

 my $result = from_javabin $binary_data;

Accepts one argument, a binary string of containing the JavaBin.

Returns a scalar representation of the data, be that undef, number, string, or reference.

This function does no error checking, hand it invalid JavaBin and it will probably die.

=head1 CAVEATS

Due to the differences between Java and Perl not all data structures can be mapped one-to-one.

An example of such mapping is a Java interator whcih becomes a Perl array during deserialization.
Additionally a Java HashMap, Named List, or Ordered Map will become a Perl hash.

=head1 TODO

=over 2

=item * C<to_javabin> serializer.

=item * XS implementation.

=back

=head1 INSPIRATION

This package was inspired by the L<Ruby JavaBin library|https://github.com/kennyj/java_bin>.
Both that library and the Java JavaBin library proved very helpful in understanding JavaBin.

=head1 AUTHOR

James Raspass E<lt>jraspass@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2013 by James Raspass

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
