package Pinkblunk::Debug;

use Exporter qw(import);

our @EXPORT = qw(error debug);

sub error {
  debug(@_);
  exit(2);
}

sub debug {
  my $fmt  = shift;
  my @args = @_;

  warn sprintf "===> $fmt\n", @args;
}


