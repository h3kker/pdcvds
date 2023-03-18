package PdcVds;

use v5.36;

use Mojo::File;
use Mojo::UserAgent;
use Mojo::JSON qw(decode_json encode_json);
use Mojo::URL;
use Mojo::Promise;
use DateTime;
use DateTime::Format::Strptime;

use open ':std', ':encoding(UTF-8)';
use utf8;

use feature 'try';
use Moose;

has 'ua' => (
    is => 'ro',
    default => sub {
        Mojo::UserAgent->new;
    }
);

has 'username' => (
    is => 'ro',
    default => 'h3kker',
);

has 'year' => (
    is => 'ro',
    lazy => 1,
    default => sub {
        DateTime->now->year;
    },
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
    lazy => 1,
    default => sub($self) {
        'data/team-'.$self->year.'.json';
    },
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
            scores => [],
        };
    }
    $team;
}

sub login($self) {
    return 1
        if $self->is_logged_in;
    say "login...";
    my $pw = `bw get password pdcvds.com`;
    die 'Could not get password'
    if $? || !$pw;
    chomp $pw;

    my $res = $self->ua->max_redirects(2)->post($self->base_url.'/savelogin.php' => form => { 
        form => 'frmlogin', 
        username => $self->username, 
        password => $pw,
    })->result;

    die 'Could not log in: '.$res->code
       unless $res->is_success;
    $self->is_logged_in(1);
}

sub _map_name($self, $name) {
    state %name_map = (
        'Sam Watson' => 'Samuel Watson',
        'Mattias Skjelmose Jensen' => 'Mattias Skjelmose',
        'Carlos Rodriguez' => 'Carlos Rodríguez',
        'Marijn van den Berg' => 'Marijn Van Den Berg',
        'Mathieu van der Poel' => 'Mathieu Van Der Poel',
        'Tadej Pogacar' => 'Tadej Pogačar',
        'Sergio Andres Higuita' => 'Sergio Higuita',
    );
    $name_map{$name} || $name;
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
    say "get team...";
    my $res = $self->ua->get($self->base_url.'/myteam.php?mw=1&y='.$self->year)->result;
    die 'Could not fetch team: '.$res->code
        unless $res->is_success;
    
    my $now = DateTime->now;

    my @riders;
    my @results;

    my $page = $res->dom;

    if ($page->at('div#content')->at('p')->text =~ m/You don't have a team for/) {
        die 'NO team in '.$self->year.'?';
    }
    my $rows = $page->at('div#content table')->children('tr');
    my @info_promises;
    $rows->tail(-1)->head(-1)->each(sub($row, $n) {
        my $cols = $row->children('td')->to_array;
        my $team = $cols->[2]->at('a')->attr('title');
        $team = $self->_map_team($team);
        my $rider_url = Mojo::URL->new($cols->[4]->at('a')->attr('href'));
        my $rider_id = $rider_url->query->param('pid');
        my $base_info = {
            pid => $rider_id,
            country => $cols->[1]->at('img')->attr('alt'),
            team_short => $cols->[2]->at('a')->text,
            team => $team,
            cat => $cols->[3]->all_text,
            name => $self->_map_name($cols->[4]->at('a')->text),
            age => $cols->[5]->text,
            price => $cols->[6]->at('a')->text+0,
            previous => $cols->[7]->text+0,
            score => $cols->[8]->text+0,
        };
        my $p = $self->get_rider_info($rider_id);
        $p->then(sub($info) {
            say "got rider info for ".$base_info->{name};
            $base_info->{pdc_teams} = $info->{teams};
            push @riders, $base_info;

            push @results, $info->{results}->@*;
        });
        push @info_promises, $p;
    });
    Mojo::Promise->all(@info_promises)->wait;
    $self->current_team->{riders} = \@riders;
    $self->current_team->{results} = \@results;
    \@riders;
}

sub get_rider_info($self, $pid, $year=$self->year) {
    say "get info for ".$pid;
    my $date_parser = DateTime::Format::Strptime->new(
        pattern => '%d-%b-%Y',
        on_error => 'croak',
    );
    return $self->ua->get_p($self->base_url.'/riders.php?mw=1&y='.$year.'&pid='.$pid)
        ->then(sub($tx) {
            my $info = {
                year => $year,
                teams => undef,
                team => undef,
                team_short => undef,
                price => undef,
                results => [],
            };
            my $res = $tx->result;
            die 'could not fetch rider info for '.$pid.': '.$res->code
                unless $res->is_success;
            my $page = $res->dom;
            $page->at('div#content table.noevents')
                 ->find('tr')->each(sub($row, $n) {
                my $cols = $row->children('td')->to_array;
                return
                    if scalar $cols->@* == 0;

                if ($cols->[0]->text eq 'Team(s)' && $cols->[1]->text ne '') {
                    $info->{teams} = $cols->[1]->text+0;
                }
                elsif ($cols->[0]->text =~ /Salary/ && $cols->[1]->text ne '') {
                    $info->{price} = $cols->[1]->text+0;
                }
                elsif ($cols->[0]->text eq 'UCI Team' && $cols->[1]->at('a')->text) {
                    my ($team, $team_short) = ($cols->[1]->at('a')->text =~ /(.*) \((\w+)\)/);
                    $info->{team} = $self->_map_team($team)
                        if $team;
                    $info->{team_short} = $team_short
                        if $team_short;
                }
            });
            my $after_results = $page->at('div#content a[name="results"]');
            my $no_results = $after_results->following('p')->first;
            if ($no_results && $no_results->at('em')->text eq 'No results found.') {
                return $info;
            }

            my $month;
            $after_results
                 ->following('table.noevents')->first
                 ->find('tr')->each(sub($row, $n) {
                my $cols = $row->children('td')->to_array;
                return
                    if scalar $cols->@* == 0;

                $month = $cols->[0]->text
                    if $cols->[0]->text;

                my $date = $date_parser->parse_datetime(
                    sprintf "%d-%s-%d" => $cols->[1]->text, $month, $year
                );
                my ($race, $stage) = split(' :: ', $cols->[2]->at('a')->text, 2);
                push $info->{results}->@*, {
                    pid => $pid,
                    race => $race,
                    stage => $stage,
                    date => $date->iso8601,
                    points => $cols->[3]->text+0,
                };
            });
            return $info;
        })
        ->catch(sub($err) {
            die 'could not fetch rider info for '.$pid.': '.$err;
        })
}

sub get_position($self) {
    $self->login;
    say "get position...";
    my $res = $self->ua->get($self->base_url.'/teams.php?mw=1&y='.$self->year)->result;
    die 'Could not fetch team: '.$res->code
        unless $res->is_success;
    
    my $page = $res->dom;
    my $rows = $page->at('div#content table')->children('tr')->tail(-1)->to_array;
    my $cur_pos;
    my $found = 0;
    for my $row ($rows->@*) {
        my $cols = $row->children('td')->to_array;
        $cur_pos = $cols->[0]->text || $cur_pos;
        if ($cols->[1]->text eq $self->username) {
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