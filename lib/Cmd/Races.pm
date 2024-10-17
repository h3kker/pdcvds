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
                $race->{$_} = $details->{$_} for qw(type category start_date end_date year);
            $self->pdc->insert_race($race);
            }
            for my $stage ($race->{stages}->@*) {
                say sprintf(" insert %s stage %s " => $race->{name}, $stage->{num});
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
            for my $stage ($stages->@*) {
                say "get results for stage ".$stage->{num};
                my $results = $self->pdc->fetch_results($stage);
                for my $result ($results->@*) {
                    $result->{stage_id} = $stage->{stage_id};
                    $result->{event_id} = $race->{event_id};
                    $self->pdc->insert_result($result);
                }
            }
        }
        else {
            my $results = $self->pdc->fetch_results($race);
            for my $result ($results->@*) {
                $result->{event_id} = $race->{event_id};
                $self->pdc->insert_result($result);
            }
        }
    }
}

true;