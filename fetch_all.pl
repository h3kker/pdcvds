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
#$pdc->get_teams;
#   $pdc->get_rider_list;
$pdc->get_results_list;
#my $oneday = $pdc->race_info( { event => 36});
#use Data::Dumper; say Dumper $oneday;
#my $stage = $pdc->race_info({ event => 506});
#use Data::Dumper; say Dumper $stage;