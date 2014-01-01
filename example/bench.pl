use strict;
use warnings;

use Benchmark::Forking 'cmpthese';
use CBOR::XS;
use Data::Dumper 'Dumper';
use Data::MessagePack;
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

my $mpack  = Data::MessagePack->new;
my $sereal = Sereal::Encoder->new;

my %alts; %alts = (
    CBOR => {
        from => sub { decode_cbor $alts{CBOR}{data} },
        pkg  => 'CBOR::XS',
        to   => sub { encode_cbor $languages },
    },
    Dump => {
        from => sub { eval $alts{Dump}{data} },
        pkg  => 'Data::Dumper',
        to   => sub { Dumper $languages },
    },
    Java => {
        from => sub { from_javabin $alts{Java}{data} },
        pkg  => 'JavaBin',
        to   => sub {   to_javabin $languages },
    },
    JSON => {
        from => sub { decode_json $alts{JSON}{data} },
        pkg  => 'JSON::XS',
        to   => sub { encode_json $languages },
    },
    MsgP => {
        from => sub { $mpack->unpack($alts{MsgP}{data}) },
        pkg  => 'Data::MessagePack',
        to   => sub { $mpack->pack($languages) },
    },
    Srel => {
        from => sub { $sereal->decode($alts{Srel}{data}) },
        pkg  => 'Sereal',
        to   => sub { $sereal->encode($languages) },
    },
    Stor => {
        from => sub {   thaw $alts{Stor}{data} },
        pkg  => 'Storable',
        to   => sub { freeze $languages },
    },
    YAML => {
        from => sub { Load $alts{YAML}{data} },
        pkg  => 'YAML::XS',
        to   => sub { Dump $languages },
    },
);

print "Modules\n\n";

{
    no strict 'refs';

    printf "%-5s%-18s%s\n", $_, $alts{$_}{pkg}, ${"$alts{$_}{pkg}::VERSION"}
        for sort keys %alts;
}

print "\nEncode\n";

cmpthese -1, { map { $_ => $alts{$_}{to} } keys %alts };

print "\nSize\n\n";

$_->{size} = length( $_->{data} = $_->{to}->() ) for values %alts;

printf "%-5s%d bytes\n", $_, $alts{$_}{size}
    for sort { $alts{$b}{size} <=> $alts{$a}{size} } keys %alts;

print "\nDecode\n";

$sereal = Sereal::Decoder->new;

cmpthese -1, { map { $_ => $alts{$_}{from} } keys %alts };
