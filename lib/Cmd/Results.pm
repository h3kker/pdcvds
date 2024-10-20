package Cmd::Results;

use v5.40;

use MooseX::App::Command;

use PdcVds;

use Mojo::JSON qw(encode_json);

extends 'Cmd';

option 'event_id' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub($self) {[]},
);

sub run($self) {
        my $races = $self->pdc->db->selectall_arrayref(q{
            SELECT * FROM races
            WHERE year=? AND (
                event_id IN (SELECT value FROM json_each(?))
                OR (? AND NOT EXISTS (
                    SELECT 1 FROM race_results WHERE races.event_id=race_results.event_id AND race_results.year=races.year)
                )
            )
        }, { Slice => {} }, $self->year, encode_json($self->event_id), scalar($self->event_id->@*) == 0);
        say "missing results for ".scalar($races->@*).' races';
    for my $race ($races->@*) {
        say "get result for race ".$race->{name};
        if ($race->{type} eq 'stage_race') {
            my $stages = $self->pdc->get_stages($race->{event_id});
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