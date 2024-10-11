package Cmd::FetchTeams;

use MooseX::App::Command;

use PdcVds;

use v5.40;

extends 'Cmd';

option 'refresh' => (
    is => 'ro',
    isa => 'Bool',
    default => false
);

sub run($self) {
    $self->pdc->fetch_teams($self->refresh);
}
true;