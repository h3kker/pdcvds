package Cmd::Races;

use v5.40;

use MooseX::App::Command;

use PdcVds;
use Mojo::JSON qw(encode_json);

extends 'Cmd';

option 'result_list' => (
    is => 'ro',
    isa => 'Bool',
    default => false,
);  

sub run($self) {
    if($self->result_list) {
        my $races = $self->pdc->fetch_race_list;
        say encode_json($races);
    } 

}

true;