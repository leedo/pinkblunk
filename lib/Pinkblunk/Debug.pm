package Pinkblunk::Debug;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT = qw(error debug info);

sub error {
  _print(ERROR => @_);
  exit(2);
}

sub info { _print(INFO => @_) }
sub debug { _print(DEBUG => @_) }

sub _print {
  my $level = shift;
  my $fmt   = shift;
  warn sprintf "%s [$level] $fmt\n", ts(), @_;
}


sub ts {
  my ($y, $o, $d, $h, $m, $s) = (localtime)[5,4,3,2,1,0];
  $o += 1;
  $y += 1900;
  sprintf "%04d-%02d-%02d %02d:%02d:%02d", $y, $o, $d, $h, $m, $s;
}

1;
