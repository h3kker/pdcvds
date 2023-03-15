#!/usr/bin/env perl
use lib qw(./lib);

use v5.36;

use ProcyclingStats;

my $pcs = ProcyclingStats->new;
my $races = $pcs->upcoming;
for my $race ($races->@*) {
    say "fetch info for ".$race->{race};
    my $info = $pcs->race_info($race->{link});
    $info->{riders} = $pcs->start_list($race->{link})->to_array;
    my $fn = $pcs->write_race($info);
    say "... saved to $fn";
}
