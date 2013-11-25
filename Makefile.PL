use v5.12;
use ExtUtils::MakeMaker;

WriteMakefile(
    ##{ $plugin->get_prereqs(0) ##}
    CCFLAGS      => '-fno-stack-protector -Wall -Wextra',
    NAME         => 'JavaBin',
    VERSION_FROM => 'lib/JavaBin.pm',
);
