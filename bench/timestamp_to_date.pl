#!/usr/bin/perl

use strict;
use warnings;

use Benchmark 'cmpthese';

my $timestamp = time;

my ( $s, $m, $h, $d, $M, $y, @date );

cmpthese -1, {
    array => sub {
        @date = gmtime $timestamp;

        $date[4] += 1;
        $date[5] += 1900;

        return sprintf '%6$04d-%5$02d-%4$02dT%3$02d:%2$02d:%1$02dZ', @date;
    },
    scalars => sub {
        ( $s, $m, $h, $d, $M, $y ) = gmtime $timestamp;

        return sprintf '%04d-%02d-%02dT%02d:%02d:%02dZ', $y+1900, $M+1, $d, $h, $m, $s;
    },
};
