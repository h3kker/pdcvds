#!/usr/bin/env perl
use lib qw(./lib);

use v5.36;

binmode(STDOUT, ":utf8");

use ProcyclingStats;
use Getopt::Long;
use Mojo::JSON 'encode_json';

my $race_links = [];
my $get_results = 0;
GetOptions(
    'race=s@' => \$race_links,
    'results' => \$get_results,
) || die("Usage!");

my $pcs = ProcyclingStats->new;
my $races;

if (scalar $race_links->@*) {
    $races = [ map { { race => $_, link => $_ } } $race_links->@* ];
}
elsif ($get_results) {
    $races = $pcs->available_results;
        }

else {
    $races = $pcs->upcoming;
}

for my $race ($races->@*) {
    my $info = $pcs->read_race($race);
    unless ($info) {
    $info = $pcs->race_info($race->{link});
    $info->{riders} ||= $pcs->start_list($race->{link})->to_array
    }
    if ($get_results) {
        $info->{results} = $pcs->results($race->{link});
    }
    my $fn = $pcs->write_race($info);
    say "... saved to $fn";
}
