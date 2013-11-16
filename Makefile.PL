use ExtUtils::MakeMaker;

WriteMakefile(
    CCFLAGS      => '-fno-stack-protector -Wall -Wextra',
    NAME         => 'JavaBin',
    VERSION_FROM => 'lib/JavaBin.pm',
);
