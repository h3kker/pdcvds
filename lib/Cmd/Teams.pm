package Cmd::Teams;

use MooseX::App::Command;

use PdcVds;

use v5.40;
use Mojo::JSON qw(encode_json);

extends 'Cmd';

option 'refresh' => (
    is => 'ro',
    isa => 'Bool',
    default => false
);

sub run($self) {
    my $team_riders_sth = $self->pdc->db->prepare(qq{
        INSERT OR REPLACE INTO team_riders(year, pid, uid) VALUES(?, ?, ?)
    }) or die "prepare team_rider stmt";
    my $team_sth = $self->pdc->db->prepare(qq{
        INSERT OR REPLACE INTO teams (uid, name, mine, year) VALUES(?, ?, ?, ?) 
    }) or die "prepare team sth";
    my $have_team_sth = $self->pdc->db->prepare(qq{SELECT count(*) FROM team_riders WHERE uid=?})
        or die "prepare have_team_sth";
    my $teams = $self->pdc->fetch_teams;
    say "got ".scalar($teams->@*).' teams';
    for my $team ($teams->@*) {
        $team_sth->execute($team->{uid}, $team->{name}, $team->{mine}, $self->year);
        $have_team_sth->execute($team->{uid});
        my $have_team = $have_team_sth->fetchrow_arrayref;
        if ($have_team->[0]) {
            say "already here, with ".$have_team->[0]." riders.";
            next unless $self->refresh;
        }
        my %riders;
        my $riders = $self->pdc->fetch_riders_for_team($team->{uid});
        say " got ".scalar $riders->@*." riders";
        for my $pid ($riders->@*) {
            my $rider = $riders{$pid};
            unless ($rider) {
                $rider = $self->pdc->get_rider($pid) ||
                    die 'unknown rider '.$pid.' please to fetch.';
                $riders{$pid} = $rider;
            }
            say "link team rider ".$rider->{name}."+".$team->{name};
            $team_riders_sth->execute($self->year, $pid, $team->{uid});
        }
    }
}
true;