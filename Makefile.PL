use ExtUtils::MakeMaker;

WriteMakefile(
    ##{ $plugin->get_prereqs(0) ##}
    CCFLAGS      => '-fno-stack-protector -fweb -Wall -Werror -Wextra',
    NAME         => 'JavaBin',
    VERSION_FROM => 'lib/JavaBin.pm',
);
