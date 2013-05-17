#!/usr/bin/perl

use strict;
use warnings;

use Benchmark 'cmpthese';
use Encode qw/decode decode_utf8 _utf8_on/;

cmpthese -1, {
    decode         => sub { decode 'UTF-8', '☃' },
    decode_utf8    => sub { decode_utf8 '☃' },
    _utf8_on       => sub {
        my $bytes = '☃';

        _utf8_on $bytes;

        return $bytes;
    },
    'utf8::decode' => sub {
        my $bytes = '☃';

        utf8::decode $bytes;

        return $bytes;
    }
};
