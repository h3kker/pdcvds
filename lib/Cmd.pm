package Cmd;

use v5.40;
use DateTime;
use MooseX::App;
use PdcVds;
use ProcyclingStats;

option 'year' => (
    isa => 'Int',
    is => 'ro',
    default => sub {DateTime->now->year },

);

has 'pdc' => (
    is => 'ro',
    lazy => true,
    default => sub($self) { PdcVds->new(year => $self->year)},
);

has 'procyclingstats' => (
    is => 'ro',
    lazy => true,
    default => sub($self) { ProcyclingStats->new},
);

sub run($self) {
    die 'need subcommand';
}

true;