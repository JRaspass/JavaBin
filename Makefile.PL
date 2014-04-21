use ExtUtils::MakeMaker;

WriteMakefile(
    ##{ $plugin->get_prereqs(0) ##}
    CCFLAGS          => '-fno-stack-protector -Wall -Werror -Wextra',
    MIN_PERL_VERSION => ##{ $meta{prereqs}{runtime}{requires}{perl} ##},
    NAME             => 'JavaBin',
    VERSION_FROM     => 'lib/JavaBin.pm',
);
