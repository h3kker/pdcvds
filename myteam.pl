#!/usr/bin/env perl
use lib qw(./lib);

use v5.36;

binmode(STDOUT, ":utf8");

use PdcVds;
use ProcyclingStats;
use DateTime;
use Getopt::Long;
my $year = DateTime->now->year;
GetOptions(
    'year=i' => \$year)
    or die("Usage!");

my $pcs = ProcyclingStats->new;
my $pdc = PdcVds->new(year => $year);

$pdc->get_current_team;
exit;

$pdc->get_riders;

$pdc->current_team->{specialties} = [];
for my $r ($pdc->current_team->{riders}->@*) {
    say "fetch pcs for ".$r->{name};
    my $spec = $pcs->rider_specialties($r->{name});
    $spec->{pid} = $r->{pid};
    push $pdc->current_team->{specialties}->@*, $spec;
}

$pdc->get_position;
#$pdc->write_team;
use Data::Dumper; say Dumper $pdc->current_team;
