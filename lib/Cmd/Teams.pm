package Cmd::Teams;

use MooseX::App::Command;

use PdcVds;

use v5.40;
use Mojo::JSON qw(encode_json);
use Mojo::Promise;

extends 'Cmd';

option 'refresh' => (
    is => 'ro',
    isa => 'Bool',
    default => false
);

sub run($self) {
    my $teams = $self->pdc->fetch_teams;
    say "got ".scalar($teams->@*).' teams';
    $teams = [ grep {
        $self->pdc->insert_team($_);
        my $have_team = $self->pdc->get_team($_->{uid});
        my $want= $have_team->{rider_count} == 0 || $self->refresh;
        if ($have_team->{rider_count}) {
            say "already here, with ".$have_team->{rider_count}." riders.";
        }
        $want;
    } $teams->@* ];
    say "fetch ".scalar $teams->@*.' teams';
    return
        unless scalar $teams->@*;
    Mojo::Promise->map({ concurrency => 5, }, sub($team) {
        return $self->pdc->fetch_riders_for_team($team->{uid})->then(sub($riders) {
            my %riders;
            say " got ".scalar $riders->@*." riders";
            for my $pid ($riders->@*) {
                my $rider = $riders{$pid};
                unless ($rider) {
                    $rider = $self->pdc->get_rider($pid) ||
                        die 'unknown rider '.$pid.' please to fetch.';
                    $riders{$pid} = $rider;
                }
                say sprintf('link rider %s:%s to %s:%s' => $rider->{pid}, $rider->{name}, $team->{uid}, $team->{name});
                $self->pdc->link_team_rider($team->{uid}, $pid, $self->year);
            }
        });
    }, $teams->@*)->wait;
}

true;