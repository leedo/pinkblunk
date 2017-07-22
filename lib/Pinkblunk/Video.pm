package Pinkblunk::Video;

use strict;
use warnings;

use Pinkblunk::Debug;
use File::Temp qw(tempdir);
use IPC::Open3 qw();
use Encode;
use Symbol qw();

use Class::Tiny qw(id url link title quality), {
    redis => sub { Redis->new },
  };

sub lookup {
  my $class = shift;
  my $id    = shift;

  my $self = $class->new( id => $id );

  for my $field (qw(url link title quality)) {
    my $value = $self->redis->hget( $id, $field );
    if (defined $value) {
      $self->$field(decode utf8 => $value);
    }
  }

  $self;
}

sub download {
  my $self = shift;
  my $dir  = tempdir();

  debug "downloading %s to %s", $self->url, $dir;

  my ($w, $r, $e, $pid);
  $e = Symbol::gensym;
  my @cmd = qw(
    ffmpeg -i - -vcodec libx264 -r 30 -pix_fmt yuv420p -strict -2 -acodec aac -map 0 -segment_time 130 -reset_timestamps 1 -f segment output%03d.mp4
  );

  my $ua = LWP::UserAgent->new;

  $ua->add_handler( response_data => sub {
    my ($res, $ua, $h, $data) = @_;
    print $w $data;
  });

  $ua->add_handler( response_header => sub  {
    my ($res, $ha, $h) = @_;

    if ($res->code != 200) {
      error "Failed to download %s: %s", $self->url, $res->status_line;
    }

    chdir($dir);
    $pid = IPC::Open3::open3($w, $r, $e, @cmd);
  });

  $ua->get( $self->url );
  close($w);

  my $stderr = join "", <$e>;
  my $stdout = join "", <$r>;
  close($r);
  close($e);

  waitpid($pid, 0);

  debug $stderr if $stderr;
  debug $stdout if $stdout;

  return glob "$dir/*.mp4";
}

1;
