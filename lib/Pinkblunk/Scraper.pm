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
use HTML::Entities qw(decode_entities);

use Class::Tiny qw(url),
  {
    ua    => sub { LWP::UserAgent->new },
    redis => sub { Redis->new },
  };

sub scrape {
  my $self = shift;
  my $content = shift;

  $self->{scraper} ||= scraper {
    process "iframe", 'iframes[]', '@src';
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
    debug "failed to fetch feed: %s", $res->status_line;
    return;
  }

  my $content = $res->decoded_content;
  my $feed = XML::Feed->parse(\$content);

  for my $entry ($feed->entries) {
    next if $self->redis->exists( $entry->id );

    debug "fetching article %s", $entry->link;
    my $res = $self->ua->get( $entry->link );

    if ($res->code != 200) {
      debug "failed to fetch url %s: %s",
        $entry->link, $res->status_line;
      next;
    }

    $self->redis->set( $entry->id, time );

    my $scrape  = $self->scrape( $res->decoded_content );
    my $videos  = $scrape->{videos};
    my $iframes = $scrape->{iframes};
    my $title   = decode_entities $entry->title;

    for my $video (@$videos) {
      my $id = $video->{id};
      my ($best) =
        map $_->[1],
        sort { $b->[0] <=> $a->[0] }
        map { my ($q) = $_->{q} =~ /([0-9]+)/; [$q, $_] }
        @{ $video->{sources} };

      debug "found video %s %s %s", $id, $best->{url}, $best->{q};

      $self->redis->hset( $id, title   => encode utf8 => $title );
      $self->redis->hset( $id, link    => encode utf8 => $entry->link  );
      $self->redis->hset( $id, url     => encode utf8 => $best->{url}  );
      $self->redis->hset( $id, quality => encode utf8 => $best->{q}    );
      $self->redis->rpush( queue => $id );
    }

    for my $iframe (@$iframes) {
      my ($id) = $iframe =~ m{^https?://(?:www\.)?youtube\.com/embed/([^/?]+)};
      if ($id) {
        debug "found youtube %s", $id;
        $self->redis->hset( $id, title   => encode utf8 => $title );
        $self->redis->hset( $id, link    => encode utf8 => $entry->link  );
        $self->redis->hset( $id, youtube => encode utf8 => "1" );
        $self->redis->rpush( queue => $id );
        next;
      }

      ($id) = $iframe =~ m{^https?://player\.vimeo\.com/video/([^/?]+)};
      if ($id) {
        debug "found vimeo %s", $id;
        $self->redis->hset( $id, title => encode utf8 => $title );
        $self->redis->hset( $id, link  => encode utf8 => $entry->link  );
        $self->redis->hset( $id, vimeo => encode utf8 => "1" );
        $self->redis->rpush( queue => $id );
        next;
      }
    }
  }
}

1;
