use ExtUtils::MakeMaker;

WriteMakefile(
    ##{ $plugin->get_prereqs(0) ##}
    ##{ "MIN_PERL_VERSION => $meta{prereqs}{runtime}{requires}{perl}," ##}
    CCFLAGS      => '-fno-stack-protector -Wall -Werror -Wextra',
    NAME         => 'JavaBin',
    VERSION_FROM => 'lib/JavaBin.pm',
);
