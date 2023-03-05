package PdcVds;

use v5.36;

use Mojo::File;
use Mojo::UserAgent;
use Mojo::JSON qw(decode_json encode_json);
use DateTime;

use feature 'try';
use Moose;

has 'ua' => (
    is => 'ro',
    default => sub {
        Mojo::UserAgent->new;
    }
);

has 'is_logged_in' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

has 'base_url' => (
    is => 'ro',
    default => 'https://www.pdcvds.com'
);

has 'team_file' => (
    is => 'ro',
    default => 'data/team-2023.json',
);

has 'current_team' => (
    is => 'ro',
    builder => '_read_current',
    lazy => 1,
);

sub _read_current($self) {
    no warnings 'experimental';
    my $team;
    try {
        $team = decode_json(Mojo::File->new($self->team_file)->slurp);
    }
    catch ($e) {
        $team = {
            standings => [],
            riders => [],
        };
    }
    $team;
}

sub login($self) {
    return 1
        if $self->is_logged_in;
    my $pw = `bw get password pdcvds.com`;
    die 'Could not get password'
    if $? || !$pw;
    chomp $pw;

    my $res = $self->ua->max_redirects(2)->post($self->base_url.'/savelogin.php' => form => { 
        form => 'frmlogin', 
        username => 'h3kker', 
        password => $pw,
    })->result;

    die 'Could not log in: '.$res->code
       unless $res->is_success;
    $self->is_logged_in(1);
}

sub _map_team($self, $team) {
    state %team_map = (
        'Israel - Premier tech' => 'Israel - Premier Tech',
        'EF Education - Easypost' => 'EF Education-EasyPost',
        'Ag2r Citroën' => 'AG2R Citroën Team',
        'Bahrain Victorious' => 'Bahrain - Victorious',
        'Bora - Hansgrohe' => 'BORA - hansgrohe',
        'Groupama - Fdj' => 'Groupama - FDJ',
        'Ineos Grenadiers' => 'INEOS Grenadiers',
        'Jumbo - Visma' => 'Jumbo-Visma',
        'Uno-X Pro Cycling' => 'Uno-X Pro Cycling Team',
    );
    $team_map{$team} || $team;
}

sub get_riders($self) {
    $self->login;
    my $res = $self->ua->get($self->base_url.'/myteam.php?mw=1&y=2023')->result;
    die 'Could not fetch team: '.$res->code
        unless $res->is_success;

    my @riders;
    my $page = $res->dom;
    my $rows = $page->at('div[id="content"] table')->children('tr');
    $rows->tail(-1)->head(-1)->each(sub($row, $n) {
        my $cols = $row->children('td')->to_array;
        my $team = $cols->[2]->at('a')->attr('title');
        $team = $self->_map_team($team);
        push @riders, {
            country => $cols->[1]->at('img')->attr('alt'),
            team_short => $cols->[2]->at('a')->text,
            team => $team,
            cat => $cols->[3]->all_text,
            name => $cols->[4]->at('a')->text,
            age => $cols->[5]->text,
            price => $cols->[6]->at('a')->text,
            previous => $cols->[7]->text,
            score => $cols->[8]->text,
        };
    });
    $self->current_team->{riders} = \@riders;
    \@riders;
}

sub get_position($self) {
    $self->login;
    my $res = $self->ua->get($self->base_url.'/teams.php?mw=1&y=2023')->result;
    die 'Could not fetch team: '.$res->code
        unless $res->is_success;
    
    my $page = $res->dom;
    my $rows = $page->at('div[id="content"] table')->children('tr')->tail(-1)->to_array;
    my $cur_pos;
    my $found = 0;
    for my $row ($rows->@*) {
        my $cols = $row->children('td')->to_array;
        $cur_pos = $cols->[0]->text || $cur_pos;
        if ($cols->[1]->text eq 'h3kker') {
            $found = 1;
            last;
        }
    }
    die 'Could not get current position'
        unless $found;
    
    $cur_pos =~ s/\.$//;
    push $self->current_team->{standings}->@*,
        { date => DateTime->now->iso8601, position => $cur_pos};
    $cur_pos;
}

sub write_team($self) {
    Mojo::File->new($self->team_file)->spurt(
        encode_json($self->current_team)
    );
}

1;