package Cmd::FetchRiders;

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
option 'all_missing' => (
    is => 'ro',
    isa => 'Bool',
);

option 'full_list' => (
    is => 'ro',
    isa => 'Bool',
);

my $process_rider  = sub ($self, $info) {
        say encode_json($info);
        my $insert_ok = $self->pdc->insert_rider($info);
        if (!$insert_ok) {
            say "skip rider ".$info->{pid}.", insert refused";
            return;
        }
        if (defined $info->{uci_team_short}) {
        $self->pdc->insert_uci_team($info->{uci_team}, $info->{uci_team_short} ,$info->{category}, $self->year);
        $self->pdc->insert_uci_team_rider($self->year, $info->{pid}, $info->{uci_team_short});
        }
        else {
            say "rider ".$info->{pid}. ' has no UCI team';
        }
    };
sub run($self) {
    my $process = sub($info) { $process_rider->($self, $info )};
    if ($self->full_list) {
        $self->pdc->get_rider_list;
    }
    elsif ($self->all_missing) {
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
            return $self->pdc->get_rider_info($missing->{pid})->then($process);
        }, $missing->@*)->wait;


    }
    elsif( defined $self->pid ) {
        $self->pdc->get_rider_info($self->pid)->then($process)->wait;
    }
    else {
        die 'need pid';
    }
}

true;