#!/bin/env perl

use 5.014;
use strict;

use Benchmark::Forking 'cmpthese';
use Data::Dumper 'Dumper';
use JavaBin;
use JSON::XS qw/decode_json encode_json/;
use Sereal;
use Storable qw/freeze thaw/;
use YAML::XS qw/Dump Load/;

$Data::Dumper::Indent = 0;

my $languages = {
    java => {
        author      => 'James Gosling',
        extensions  => [ qw/.jar .java .class/ ],
        native_bool => \1,
        released    => '1996-01-23',
        TIOBE_rank  => 2,
    },
    perl => {
        author      => 'Larry Wall',
        extensions  => [ qw/.pl .pm .pod .t/ ],
        native_bool => \0,
        released    => '1987-12-18',
        TIOBE_rank  => 12,
    },
    php => {
        author      => 'Rasmus Lerdorf',
        extensions  => [ qw/.php/ ],
        native_bool => \1,
        released    => '1995-06-08',
        TIOBE_rank  => 5,
    },
    python => {
        author      => 'Guido van Rossum',
        extensions  => [ qw/.py .pyc .pyd .pyo .pyw/ ],
        native_bool => \1,
        released    => '1991-02-20',
        TIOBE_rank  => 8,
    },
    ruby => {
        author      => 'Yukihiro Matsumoto',
        extensions  => [ qw/.rb .rbw/ ],
        native_bool => \1,
        released    => '1995-12-21',
        TIOBE_rank  => 13,
    },
};

my $sereal = Sereal::Encoder->new;

my %alts; %alts = (
    'Data::Dumper' => {
        from => sub { eval $alts{'Data::Dumper'}{data} },
        to   => sub { Dumper $languages },
    },
    JavaBin => {
        from => sub { from_javabin $alts{JavaBin}{data} },
        to   => sub {   to_javabin $languages },
    },
    'JSON::XS' => {
        from => sub { decode_json $alts{'JSON::XS'}{data} },
        to   => sub { encode_json $languages },
    },
    Sereal => {
        from => sub { $sereal->decode($alts{Sereal}{data}) },
        to   => sub { $sereal->encode($languages) },
    },
    Storable => {
        from => sub {   thaw $alts{Storable}{data} },
        to   => sub { freeze $languages },
    },
    'YAML::XS' => {
        from => sub { Load $alts{'YAML::XS'}{data} },
        to   => sub { Dump $languages },
    },
);

say 'Encode';

cmpthese -1, { map { $_ => $alts{$_}{to} } keys %alts };

say "\nSize\n";

$_->{size} = length( $_->{data} = $_->{to}->() ) for values %alts;

printf "%-13s%d bytes\n", $_, $alts{$_}{size}
    for sort { $alts{$b}{size} <=> $alts{$a}{size} } keys %alts;

say "\nDecode";

$sereal = Sereal::Decoder->new;

cmpthese -1, { map { $_ => $alts{$_}{from} } keys %alts };
