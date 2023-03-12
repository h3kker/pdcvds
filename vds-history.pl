#!/usr/bin/env perl
use lib qw(./lib);

use v5.36;

use PdcVds;
use ProcyclingStats;
use Mojo::File;
use Mojo::Collection;
use Mojo::JSON qw(encode_json);

my $pcs = ProcyclingStats->new;

# initialize with team for current year
my $teams = Mojo::Collection->new(
    PdcVds->new->current_team->{riders}
);
for my $year (2019..2022) {
    my $pdc = PdcVds->new(year => $year);
    if (Mojo::File->new($pdc->team_file)->stat) {
        push $teams->@*, $pdc->current_team->{riders};
        next;
    }

    $pdc->get_riders;
    $pdc->current_team->{specialties} = [];
    for my $r ($pdc->current_team->{riders}->@*) {
        say "fetch pcs for ".$r->{name};
        my $spec = $pcs->rider_specialties($r->{name});
        $spec->{pid} = $r->{pid};
        push $pdc->current_team->{specialties}->@*, $spec;
    }
    $pdc->write_team;
    push $teams->@*, $pdc->current_team->{riders};
}
my $riders = $teams->flatten->uniq(sub ($r) { $r->{pid} })->map(sub ($r) {
    return {
        name => $r->{name},
        pid => $r->{pid},
        seasons => [],
        results => [],
    }
});

my $pdc = PdcVds->new;
for my $cmp_year (2019..2023) {
    say "get compare year $cmp_year";
    my $p = Mojo::Promise->map({ concurrency => 3 }, sub ($r) {
        $pdc->get_rider_info($r->{pid}, $cmp_year)->then(sub ($info) {
            push $r->{results}->@*, (delete $info->{results})->@*;
            push $r->{seasons}->@*, $info;
        });
    }, $riders->@*)->wait;
}
Mojo::File->new('data/history.json')->spurt(encode_json $riders);

