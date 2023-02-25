#!/usr/bin/env perl

use v5.36;

use Mojo::UserAgent;
use Mojo::JSON qw(encode_json);
use Path::Tiny;
use Mojo::Util qw(slugify);
use utf8;

my $start_url = shift @ARGV ||
  die "Usage: $0 [url]";

my $ua = Mojo::UserAgent->new;

my @subs = ('result/overview', 'gc/overview');
my $ov_res;
for my $sub (@subs) {
  my $overview_url = $start_url;
  $overview_url =~ s,(result/)?startlist$,$sub,;
  say $overview_url;
  $ov_res = $ua->get($overview_url)->result;
  die 'Unable to fetch: '.$ov_res->code
    unless $ov_res->is_success;
  
  unless ($ov_res->dom->at('div.main h1')->text eq 'Page not found') {
    last;
  }
}


my $infos = $ov_res->dom->at('ul.infolist')->find('li')->to_array;
my $start_date = $infos->[0]->find('div')->last->text;
my $end_date = $infos->[1]->find('div')->last->text;

my $res = $ua->get($start_url)->result;
die 'Unable to fetch: '.$res->code
  unless $res->is_success;

my $race = $res->dom->at('div.main h1')->text;

my $list = $res->dom->at('ul.startlist_v3')->find('li.team');

my $riders = $list->map(sub($t) {
  my $team = $t->at('b a')->text;
  return $t->find('ul li')->map(sub($r) {
    my $number = $r->text;
    $number =~ tr/ //d;
    my $name = $r->at('a span')->text;
    $name =~ /^([\p{Upper}\-'ß ]+) (.+)$/;
    die "$name does not match"
      unless $1 && $2;
    return {
      name => sprintf("%s %s" => $2, join('', map { ucfirst(lc $_) } split "([ '-])", $1)),
      team => $team,
      number => $number,
    }
  });
})->flatten;

path("race-".$start_date."-".slugify($race).".json")->spew(
  encode_json({
    race => $race,
    start_date => $start_date,
    end_date => $end_date,
    riders => $riders->TO_JSON
  })
);
