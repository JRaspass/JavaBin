package JavaBin;
# ABSTRACT: Apache Solr JavaBin (de)serializer

use XSLoader 0.14;

XSLoader::load();

sub import {
    *{ caller() . '::from_javabin' } = \&from_javabin;
}

1;

__END__

=head1 SYNOPSIS

 use JavaBin;

 my $result = from_javabin $binary_data;

=head1 DESCRIPTION

JavaBin is a compact binary format used by L<Apache Solr|http://lucene.apache.org/solr>.

For more information on this format see the L<Solr Wiki|http://wiki.apache.org/solr/javabin>.

This package provides a deserializer for this format, with a serializer planned.

=func from_javabin

 my $result = from_javabin $binary_data;

Accepts one argument, a binary string of containing the JavaBin.

Returns a scalar representation of the data, be that undef, number, string, or reference.

This function does no error checking, hand it invalid JavaBin and it will probably die.

=head1 CAVEATS

To (de)serialize long floats and ints this package requires a 64bit Perl.
That said, it won't actually throw unless it encounters such data, and therefore
the tests for such data are skipped on 32bit platforms.

Technically this limitation could be worked around by use of L<bigint> or such.
But the added complexity and maintanace cost would outweight the benifit.

Due to the differences between Java and Perl not all data structures can be mapped one-to-one.

An example of such mapping is a Java interator whcih becomes a Perl array during deserialization.
Additionally a Java HashMap, Named List, or Ordered Map will become a Perl hash.

=head1 TODO

=for :list
* C<to_javabin> serializer.
* XS implementation.

=head1 INSPIRATION

This package was inspired by the L<Ruby JavaBin library|https://github.com/kennyj/java_bin>.
Both that library and the Java JavaBin library proved very helpful in understanding JavaBin.
