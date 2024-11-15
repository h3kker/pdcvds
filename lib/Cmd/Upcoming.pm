package Cmd::Upcoming;

use v5.40;

use MooseX::App::Command;

use ProcyclingStats;
use JSON::PP;

extends 'Cmd';

sub run($self) {
  #say encode_json $self->procyclingstats->upcoming;
  say encode_json $self->procyclingstats->start_list('https://www.procyclingstats.com/race/boucles-de-la-mayenne/2024/overview')->to_array;
}