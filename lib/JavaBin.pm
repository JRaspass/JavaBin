package JavaBin 0.7;

require DynaLoader;

DynaLoader::dl_install_xsub(
    undef,
    DynaLoader::dl_find_symbol(
        DynaLoader::dl_load_file(
            scalar DynaLoader::dl_findfile(map("-L$_/auto/JavaBin", @INC), 'JavaBin')
        ),
        'boot'
    )
)->();

sub import {
    shift;

    my $caller = caller;

    *{ $caller . "::$_" } = \&$_ for @_ ? @_ : qw/from_javabin to_javabin/;
}

1;
