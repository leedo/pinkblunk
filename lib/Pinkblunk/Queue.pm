package Pinkblunk::Queue;

use Class::Tiny qw(), {
    redis => sub { Redis->new },
  };

sub jobs {
  my $self = shift;
  $self->redis->lpop("queue");
}

1;
