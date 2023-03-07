#!/usr/bin/env perl
use lib qw(./lib);

use v5.36;

use ProcyclingStats;
use PdcVds;


my $pcs = ProcyclingStats->new;
my $pdc = PdcVds->new;
my $team = $pdc->current_team;
$team->{specialties} //= [];
for my $r ($team->{riders}->@*) {
    say "fetch pcs for ".$r->{name};
    my $spec = $pcs->rider_specialties($r->{name});
    $spec->{pid} = $r->{pid};
    push $team->{specialties}->@*, $spec;
}
$pdc->write_team;

