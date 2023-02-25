#!/usr/bin/env perl

use v5.36;

use Mojo::File;
use Mojo::UserAgent;
use Mojo::JSON qw(encode_json);

my $ua = Mojo::UserAgent->new;

my $pw = Mojo::File->new('.pw')->slurp;
chomp $pw;

my $res = $ua->max_redirects(2)->post('https://www.pdcvds.com/savelogin.php' => form => { 
    form => 'frmlogin', 
    username => 'h3kker', 
    password => $pw,
  })->result;

die 'Could not log in: '.$res->code
  unless $res->is_success;

$res = $ua->get('https://www.pdcvds.com/myteam.php?mw=1&y=2023')->result;
die 'Could not fetch team: '.$res->code
  unless $res->is_success;

my %team_map = (
  'Israel - Premier tech' => 'Israel - Premier Tech',
  'EF Education - Easypost' => 'EF Education-EasyPost',
  'Ag2r Citroën' => 'AG2R Citroën Team',
  'Bahrain Victorious' => 'Bahrain - Victorious',
  'Bora - Hansgrohe' => 'BORA - hansgrohe',
  'Groupama - Fdj' => 'Groupama - FDJ',
  'Ineos Grenadiers' => 'INEOS Grenadiers',
  'Jumbo - Visma' => 'Jumbo-Visma',
  'Uno-X Pro Cycling' => 'Uno-X Pro Cycling Team',
);

my @riders;
my $page = $res->dom;
my $rows = $page->at('div[id="content"] table')->children('tr');
$rows->tail(-1)->head(-1)->each(sub($row, $n) {
  my $cols = $row->children('td')->to_array;
  my $team = $cols->[2]->at('a')->attr('title');
  $team = $team_map{$team} || $team;
  push @riders, {
    country => $cols->[1]->at('img')->attr('alt'),
    team_short => $cols->[2]->at('a')->text,
    team => $team,
    cat => $cols->[3]->all_text,
    name => $cols->[4]->at('a')->text,
    age => $cols->[5]->text,
    price => $cols->[6]->at('a')->text,
    previous => $cols->[7]->text,
    score => $cols->[8]->text,
  };
});

say encode_json(\@riders);
