use strict;
use strict;
use warnings;
use ExtUtils::MakeMaker;

my ($mm) = $ExtUtils::MakeMaker::VERSION =~ /^([^_]+)/;

WriteMakefile(
  NAME         => 'Sonde-Parser',
  VERSION_FROM => 'sonde-parser.pl',
  ABSTRACT     => 'Processes WINDSOND data file',
  AUTHOR       => 'Adam C. Abernathy <adamabernathy@gmail.com>',

  ($mm < 6.3002 ? () : ('LICENSE' => 'apache-2.0')),

  test => {TESTS => 'sonde-parser.pl'}
);
