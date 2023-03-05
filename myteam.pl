#!/usr/bin/env perl
use lib qw(./lib);

use v5.36;

use PdcVds;

my $pdc = PdcVds->new;
$pdc->get_riders;
$pdc->get_position;
$pdc->write_team;