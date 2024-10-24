package Cmd::Races;

use v5.40;

use MooseX::App::Command;

use PdcVds;
#use Mojo::JSON qw(encode_json);
use JSON::PP;

extends 'Cmd';

option 'list' => (
    is => 'ro',
    isa => 'Bool',
    default => false,
);

option 'event_id' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub($self) {[]},
);

sub run($self) {
    if($self->list) {
        my $races = $self->pdc->fetch_race_list;
        for my $race ($races->@*) {
            my $event = $self->pdc->get_race($race->{event_id});
            unless($event && $event->{type} && $event->{start_date}) {
                my $details = $self->pdc->fetch_race($race->{event_id});
                $self->pdc->insert_race($details);
            }
            else {
                say "skip ".$race->{name}." already here";
            }
        }
        #say encode_json($races);
    }
    else {
        my $races = $self->pdc->db->selectall_arrayref(q{
      SELECT event_id FROM races
            WHERE year=? AND (
                event_id IN (SELECT value FROM json_each(?))
                OR (? AND (
                    type IS NULL OR start_date IS NULL OR (
                    type = 'stage_race' AND NOT EXISTS (
                    SELECT 1 FROM stages WHERE races.event_id=stages.event_id AND stages.date IS NOT NULL)
                )))
            )
        }, { Slice => {} }, $self->year, encode_json($self->event_id), !scalar($self->event_id->@*)> 0 );
            # if no event_id defined we fetch all events without details or stages
        say "fetch missing info for ".scalar($races->@*).' races';
        for my $race ($races->@*) {
            my $race_info = $self->pdc->fetch_race($race->{event_id});
            $self->pdc->insert_race($race_info);
        }
    }
}

true;