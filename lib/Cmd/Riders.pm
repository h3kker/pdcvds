package Cmd::Riders;

use MooseX::App::Command;
use PdcVds;
use Mojo::Promise;
use Mojo::JSON qw(encode_json);
use v5.40;

extends 'Cmd';

option 'pid' => (
    is => 'ro',
    isa => 'Int',
    #required => true,
);

option 'full_list' => (
    is => 'ro',
    isa => 'Bool',
);

sub run($self) {
    my $process = sub ($info) {
        say encode_json($info);
        my $insert_ok = $self->pdc->insert_rider($info);
        if (!$insert_ok) {
            say "skip rider ".$info->{pid}.", insert refused";
            return;
        }
        if (defined $info->{uci_team_short}) {
            $self->pdc->insert_uci_team({
                name => $info->{uci_team},
                short => $info->{uci_team_short},
                cat => $info->{category},
                year => $self->year,
            });
        $self->pdc->link_uci_team_rider($info->{uci_team_short}, $info->{pid}, $self->year);
        }
        else {
            say "rider ".$info->{pid}. ' has no UCI team';
        }
    };
    if ($self->full_list) {
        my @riders = $self->pdc->fetch_rider_list;
        for my $rider (@riders) {
            $self->pdc->insert_rider($rider);
        $self->pdc->insert_rider_price($rider->{pid}, $rider->{price}, $self->year);
        }
    }
    elsif(defined $self->pid) {
        $self->pdc->fetch_rider_info($self->pid)->then($process)->wait;
    } 
    else {
        my $missing = $self->pdc->db->selectall_arrayref(qq(
            SELECT pid FROM riders 
             WHERE (dob IS NULL 
             OR NOT EXISTS (SELECT 1 FROM uci_team_riders WHERE pid=riders.pid))
             AND EXISTS (SELECT 1 FROM riders_seen WHERE pid=riders.pid AND year=?)
             ), { Slice => {}}, $self->year);
        say "fetch ".scalar($missing->@*).' promises';
        unless(scalar $missing->@*) {
            say "all done!";
            return;
        }
        my $p = Mojo::Promise->map({ concurrency => 5 }, sub($missing) {
            return $self->pdc->fetch_rider_info($missing->{pid})->then($process);
        }, $missing->@*)->wait;
    }
}
true;