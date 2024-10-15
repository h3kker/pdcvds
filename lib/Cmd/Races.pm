package Cmd::Races;

use v5.40;

use MooseX::App::Command;

use PdcVds;
use Mojo::JSON qw(encode_json);

extends 'Cmd';

option 'list' => (
    is => 'ro',
    isa => 'Bool',
    default => false,
);
option 'results' => (
    is => 'ro',
    isa => 'Bool',
    default => false,
);

option 'event_id' => (
    is => 'ro',
    isa => 'Int',
);

sub run($self) {
    if($self->list) {
        my $races = $self->pdc->fetch_race_list;
        for my $race ($races->@*) {
            say sprintf("insert %s %s" => $race->{type}, $race->{name});
            $self->pdc->insert_race($race);
            for my $stage ($race->{stages}->@*) {
                say sprintf(" insert %s stage %s " => $race->{name}, $stage->{stage_num});
                $self->pdc->insert_stage($stage);
            }
        }
        #say encode_json($races);
    }
    elsif($self->results) {
        die 'need event_id'
            unless $self->event_id;
        my $result = $self->pdc->fetch_race_info($self->event);
        say encode_json $result;
    }

}

true;