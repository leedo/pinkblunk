package Pinkblunk::Scraper;

use strict;
use warnings;

use Pinkblunk::Debug;
use Redis;
use LWP::UserAgent;
use XML::Feed;
use Web::Scraper;
use Encode;
use List::Util qw(first);

use Class::Tiny qw(url),
  {
    ua    => sub { LWP::UserAgent->new },
    redis => sub { Redis->new },
  };

sub scrape {
  my $self = shift;
  my $content = shift;

  $self->{scraper} ||= scraper {
    process ".video-container", 'videos[]' => scraper {
      process "video", id => '@data-videoid';
      process "video source", 'sources[]', {
        q => '@data-quality',
        url => '@src',
      };
    },
  };

  $self->{scraper}->scrape($content);
}

sub fetch {
  my $self = shift;
  info "fetching RSS at %s", $self->url;
  my $res = $self->ua->get( $self->url );

  if ($res->code != 200) {
    error "failed to fetch feed: %s", $res->status_line;
  }

  my $content = $res->decoded_content;
  my $feed = XML::Feed->parse(\$content);

  for my $entry ($feed->entries) {
    if ($self->redis->exists( $entry->id )) {
      debug "skipping %s", $entry->link;
      next;
    }

    debug "fetching article %s", $entry->link;
    my $res = $self->ua->get( $entry->link );

    if ($res->code != 200) {
      error "failed to fetch url %s: %s",
        $entry->link, $res->status_line;
    }

    $self->redis->set( $entry->id, time );

    my $scrape = $self->scrape( $res->decoded_content );
    my $videos = $scrape->{videos};

    for my $video (@$videos) {
      my $id = $video->{id};
      my ($best) = sort { $b->{q} <=> $a->{q} } @{ $video->{sources} };

      debug "found video %s %s %s", $id, $best->{url}, $best->{q};

      $self->redis->hset( $id, title   => encode utf8 => $entry->title );
      $self->redis->hset( $id, link    => encode utf8 => $entry->link  );
      $self->redis->hset( $id, url     => encode utf8 => $best->{url}  );
      $self->redis->hset( $id, quality => encode utf8 => $best->{q}    );
      $self->redis->rpush( queue => $id );
    }
  }
}

1;
