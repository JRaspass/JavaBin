use ExtUtils::MakeMaker;

WriteMakefile(
    CCFLAGS      => '-fno-stack-protector',
    NAME         => 'JavaBin',
    VERSION_FROM => 'lib/JavaBin.pm',
);
