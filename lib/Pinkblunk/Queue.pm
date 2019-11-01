package Pinkblunk::Queue;

use strict;
use warnings;

use Class::Tiny qw(), {
    redis => sub { Redis->new },
  };

sub jobs {
  my $self = shift;
  $self->redis->lpop("queue");
}

sub fail {
  my ($self, $id) = @_;
  $self->redis->rpush("queue", $id);
}

1;
