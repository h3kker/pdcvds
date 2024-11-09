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
                    OR (? AND (
                    NOT EXISTS (SELECT 1 FROM race_results WHERE races.event_id=race_results.event_id AND race_results.year=races.year)
                        OR event_id IN ( SELECT event_id FROM stages WHERE stages.year=races.year AND NOT EXISTS (SELECT 1 FROM race_results rr WHERE rr.stage_id=stages.stage_id AND rr.year=stages.year))
                        )
                    )
            )
        }, { Slice => {} }, $self->year, encode_json($self->event_id), scalar($self->event_id->@*) == 0);
        say "missing results for ".scalar($races->@*).' races';
        my @promises;
        for my $race ($races->@*) {
            $self->pdc->db->do(q{DELETE FROM race_results WHERE event_id=? AND year=?}, undef, $race->{event_id}, $self->year);
            if ($race->{type} eq 'stage_race') {
                my $stages = $self->pdc->get_stages($race->{event_id});
                for my $stage ($stages->@*) {
                    push @promises, $self->pdc->fetch_results($stage)->then(sub($results) {
                        say sprintf('got results for %s stage %s' => $race->{name}, $stage->{num});
                        for my $result ($results->@*) {
                            $result->{stage_id} = $stage->{stage_id};
                            $result->{event_id} = $race->{event_id};
                            $self->pdc->insert_result($result);
                        }
                    });
                }
            }
            else {
                push @promises, $self->pdc->fetch_results($race)->then(sub($results) {
                    say sprintf('got results for race %s' => $race->{name});
                    for my $result ($results->@*) {
                        $result->{event_id} = $race->{event_id};
                        $self->pdc->insert_result($result);
                    }
                });
            }
    }
    say sprintf 'running %s promises' => scalar @promises;
    for my $promise (@promises) {
        $promise->catch( sub($e) {
            warn 'failed: '.$e;
            #sleep 5;
            #push @promises, $promise;
        })->wait
    }
    #Mojo::Promise->map({ concurrency => 1}, sub { return $_[0]}, @promises)->wait
}
true;