#!/usr/bin/env perl
use lib qw(./lib);

=head1 NAME

vds-history.pl - Get historic PDC VDS team data

=head1 SYNOPSIS

vds-history.pl [options]

 Options:
    --year      which year

=cut

use v5.36;

use Getopt::Long;
my $year;
GetOptions("year=i" => \$year)
    or pod2usage(1);
pod2usage("missing year")
    unless $year;

use PdcVds;
use ProcyclingStats;

my $pcs = ProcyclingStats->new;
my $pdc = PdcVds->new(year => $year);

$pdc->get_riders;

$pdc->current_team->{specialties} = [];
for my $r ($pdc->current_team->{riders}->@*) {
    say "fetch pcs for ".$r->{name};
    my $spec = $pcs->rider_specialties($r->{name});
    $spec->{pid} = $r->{pid};
    push $pdc->current_team->{specialties}->@*, $spec;
}

for my $cmp_year (2019..2023) {
    next if $year == $cmp_year;
    say "get compare year $cmp_year";
    my @info_promises;
    for my $r ($pdc->current_team->{riders}->@*) {
        my $p = $pdc->get_rider_info($r->{pid}, $cmp_year);
        $p->then(sub($info) {
            say "got $cmp_year info for ".$r->{name};
            push $pdc->current_team->{results}->@*,
                $info->{results}->@*;
        });
        push @info_promises, $p;
    }
    Mojo::Promise->all(@info_promises)->wait;
}

$pdc->write_team;