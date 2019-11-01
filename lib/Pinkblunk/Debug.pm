package Pinkblunk::Debug;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT = qw(error debug info);

use constant {
  ERROR => 0,
  INFO  => 1,
  DEBUG => 2,
};

my @DISPLAY = (
  "ERROR",
  "INFO",
  "DEBUG",
);
  
our $LEVEL = INFO;

sub error {
  _print(ERROR => @_) if $LEVEL >= ERROR;
  exit(2);
}

sub info  { _print(INFO, @_)  if $LEVEL >= INFO }
sub debug { _print(DEBUG, @_) if $LEVEL >= DEBUG }

sub _print {
  my $level = shift;
  my $fmt   = shift;
  my @args  = @_;
  if (@args) {
    warn sprintf "%s [%s] $fmt\n", ts(), $DISPLAY[$level], @args;
  }
  else {
    warn sprintf( "%s [%s]", ts(), $DISPLAY[$level] ) . " $fmt\n";
  }
}


sub ts {
  my ($y, $o, $d, $h, $m, $s) = (localtime)[5,4,3,2,1,0];
  $o += 1;
  $y += 1900;
  sprintf "%04d-%02d-%02d %02d:%02d:%02d", $y, $o, $d, $h, $m, $s;
}

1;
