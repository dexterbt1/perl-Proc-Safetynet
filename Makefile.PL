use 5.008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Safetynet',
    VERSION_FROM      => 'lib/Safetynet.pm', # finds $VERSION
    PREREQ_PM         => {
        'Test::Exception'                   => 0.25,
        #'JSON::XS'                          => 2.21,
        'Moose'                             => 0.51,
        'Proc::Daemon'                      => 0.03,
    }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Safetynet.pm', # retrieve abstract from module
       AUTHOR         => 'Dexter Tad-y <dexter@>') : ()),
);
