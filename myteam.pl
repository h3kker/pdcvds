#!/usr/bin/env perl
use lib qw(./lib);

use v5.36;

binmode(STDOUT, ":utf8");

use PdcVds;
use ProcyclingStats;

my $pcs = ProcyclingStats->new;
my $pdc = PdcVds->new;

$pdc->get_riders;

$pdc->current_team->{specialties} = [];
for my $r ($pdc->current_team->{riders}->@*) {
    say "fetch pcs for ".$r->{name};
    my $spec = $pcs->rider_specialties($r->{name});
    $spec->{pid} = $r->{pid};
    push $pdc->current_team->{specialties}->@*, $spec;
}

$pdc->get_position;
$pdc->write_team;
