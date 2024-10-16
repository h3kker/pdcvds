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
            my $event = $self->pdc->get_race($race->{event_id});
            unless($event && $event->{type} && $event->{start_date}) {
                my $details = $self->pdc->fetch_race($race->{event_id});
                $race->{$_} = $details->{$_} for qw(type category start_date end_date);
            $self->pdc->insert_race($race);
            }
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
        my $race = $self->pdc->get_race($self->event_id) || die 'no such race';
        if ($race->{type} eq 'stage_race') {
            my $stages = $self->pdc->get_stages($self->event_id);
            say encode_json $stages;
            say encode_json $self->pdc->fetch_results($stages->[4]);
        }
        else {
            say encode_json $self->pdc->fetch_results($race);
        }
    }
}

true;