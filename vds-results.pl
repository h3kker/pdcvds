#!/usr/bin/env perl
use lib qw(./lib);

use v5.36;

use ProcyclingStats;
use Getopt::Long;
use PdcVds;

my $year = 2023;
my $race_links = [];
GetOptions(
    'race=s@' => \$race_links,
    'year=i' => \$year,
) or die("Usage!");

use Mojo::File;
use Mojo::Collection;
use Mojo::JSON qw(encode_json);

my $pdc = PdcVds->new(year => $year);

my $races;
if (scalar $race_links->@*) {
    $races = [ map { { link => $_ } } $race_links->@* ];
}
else {
    $races = $pdc->results_list;
}

for my $race ($races->@*) {
    my $rr = $pdc->race_info($race);
    use Data::Dumper; say Dumper $rr;
}
