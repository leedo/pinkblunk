package Pinkblunk::Twitter;

use Pinkblunk::Debug;
use Net::OAuth;
use LWP::UserAgent;
use JSON::XS;
use Class::Tiny qw( consumer_key consumer_secret access_token access_token_secret ),
  {
    ua => sub  { LWP::UserAgent->new }
  };

sub upload {
  my $self = shift;
  my $file = shift;
  my $len  = (stat($file))[7];

  my $media_id = $self->upload_init($len);
  $self->upload_append($file, $len, $media_id);
  $self->upload_finalize($media_id);

  my $status = $self->upload_status($media_id);

  while ($status->{state} eq "in_progress") {
    sleep $status->{check_after_secs};
    $status = $self->upload_status($media_id);
  }

  if ($status->{state} ne "succeeded") {
    debug encode_json $status;
    error "upload failed %s", $file;
  }

  $media_id;
}

sub post {
  my $self = shift;
  my $video = shift;
  my @medias = @_;

  my $title = $video->title;
  $title =~ s/\s*-[^-]*Video$//;

  my $i = 1;
  for my $media_id (@medias) {
    my $t = $title;

    if (@medias > 1) {
      $t .= sprintf " %s/%s %s", $i++, scalar(@medias), $video->link;
    }
    else {
      $t .= sprintf " %s", $video->link;
    }

    $self->status( $t, $media_id );
  }
}

sub status {
  my $self = shift;
  my $title = shift;
  my $media_id = shift;

  my $req = $self->req(
    request_method => "POST",
    request_url => 'https://api.twitter.com/1.1/statuses/update.json',
    extra_params => {
      status => $title,
      media_ids => $media_id,
    }
  );

  my $res = $self->ua->post(
    $req->request_url,
    Content => $req->to_post_body
  );

  if ($res->code != 200) {
    my $error = decode_json $res->content;
    info "got %s", $res->status_line;
    error $error->{error};
  }
}

sub req {
  my $self = shift;
  my $request = Net::OAuth->request("protected_resource")->new(
    version => "1.0",
    signature_method => "HMAC-SHA1",
    timestamp => time,
    nonce => time ^ $$ ^ int(rand 2**32),
    consumer_key => $self->consumer_key,
    consumer_secret=> $self->consumer_secret,
    token =>  $self->access_token,
    token_secret=> $self->access_token_secret,
    @_,
  );
  $request->sign;
  $request;
}

sub upload_finalize {
  my $self = shift;
  my $media_id = shift;

  debug "FINALIZE %s", $media_id;

  my $req = $self->req(
    request_method => "POST",
    request_url => 'https://upload.twitter.com/1.1/media/upload.json',
    extra_params => {
      command => "FINALIZE",
      media_id => $media_id,
    }
  );

  my $res = $self->ua->post(
    $req->request_url,
    Content => $req->to_post_body
  );

  if ($res->code != 200) {
    my $error = decode_json $res->content;
    info "got %s", $res->status_line;
    error $error->{error};
  }
}

sub upload_status {
  my $self = shift;
  my $media_id = shift;

  debug "STATUS %s", $media_id;

  my $req = $self->req(
    request_method => "GET",
    request_url => 'https://upload.twitter.com/1.1/media/upload.json',
    extra_params => {
      command => "STATUS",
      media_id => $media_id,
    }
  );

  my $res = $self->ua->get($req->to_url);

  if ($res->code != 200) {
    my $error = decode_json $res->content;
    info "got %s", $res->status_line;
    error $error->{error};
  }

  my $data = decode_json $res->content;
  return $data->{"processing_info"};
}

sub upload_append {
  my $self = shift;
  my $file = shift;
  my $len  = shift;
  my $media_id = shift;

  my $pos = 0;
  my $seg = 0;

  open my $fh, '<', $file;

  debug "total length $len";
  while ( $pos < $len ) {
    debug "reading from pos $pos";
    read($fh, my $chunk, 4 * 1024 * 1024);

    debug "read %s", length $chunk;
    debug "APPEND %s segment %s", $file, $seg;

    my $req = $self->req(
      request_method => "POST",
      request_url => 'https://upload.twitter.com/1.1/media/upload.json',
      extra_params => {}
    );
    
    my $res = $self->ua->post(
      $req->request_url,
      Authorization => $req->to_authorization_header,
      Content_Type  => 'form-data',
      Content       => [
        command       => "APPEND",
        media_id      => $media_id,
        segment_index => $seg,
        media         => $chunk,
      ]
    );

    if ($res->code != 204) {
      my $error = decode_json $res->content;
      info "got %s", $res->status_line;
      error $error->{error};
    }

    $pos = tell $fh;
    $seg++;
  }
}


sub upload_init {
  my $self  = shift;
  my $len   = shift;

  debug "INIT";

  my $req = $self->req(
    request_method => "POST",
    request_url => 'https://upload.twitter.com/1.1/media/upload.json',
    extra_params => {
      command => "INIT",
      media_type => "video/mp4",
      total_bytes => $len,
      media_category => 'tweet_video',
    }
  );

  my $res = $self->ua->post(
    $req->request_url,
    Content => $req->to_post_body
  );
  
  if ($res->code != 202) {
    my $error = decode_json $res->content;
    info "got %s", $res->status_line;
    error $error->{error};
  }

  my $data = decode_json($res->content);
  $data->{media_id};
}

1;
