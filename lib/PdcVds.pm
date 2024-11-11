package PdcVds;

use v5.40;

use Mojo::File;
use Mojo::UserAgent;
use Mojo::JSON qw(decode_json encode_json);
use Mojo::URL;
use Mojo::Promise;
use DateTime;
use DateTime::Format::Strptime;
use DBI;
use Parse::CSV;
use File::Temp qw(tempfile);
use Carp;


use open ':std', ':encoding(UTF-8)';
use utf8;

use feature 'try';
use Moose;

has 'ua' => (
    lazy => true,
    is => 'ro',
    default => sub {
        my $ua = Mojo::UserAgent->new;
        $ua->connect_timeout(10);
        $ua;
    }
);
has 'db' => (
    is => 'ro',
    lazy => true,
    default => sub {
        my $dbh = DBI->connect("dbi:SQLite:dbname=pdcvds.db","","");
        $dbh->do('PRAGMA foreign_keys = ON');
        $dbh->do('PRAGMA encoding="UTF-8"');
        $dbh->{AutoCommit} = 1;
        $dbh->{RaiseError} = 1;
        $dbh;
    }
);

sub _gen_insert($self, $table, $cols, $info) {
    my $sth = $self->db->prepare(sprintf(q{ INSERT OR REPLACE INTO %s(%s) VALUES (%s)} =>
        $table,
        join(', ', $cols->@*), 
        join(', ', map { '?' } $cols->@* )
    )
);
    $sth->execute(map { $info->{$_}} $cols->@* );

}
sub insert_race($self, $race) {
    my @cols = qw(event_id name type category start_date end_date country year);
    say sprintf("insert %s %s" => $race->{type}, $race->{name});
    $self->_gen_insert('races', \@cols, $race);
    if ($race->{type} eq 'stage_race') {
            for my $stage ($race->{stages}->@*) {
                say sprintf(" insert %s stage %s " => $race->{name}, $stage->{num});
                $self->insert_stage($stage);
            }
    }
}

sub insert_stage($self, $stage) {
    unless ($stage->{stage_id}) {
        say "skip, no id";
        return;
    }
    my @cols = qw(event_id stage_id num year date);
    $self->_gen_insert('stages', \@cols, $stage);
}

    sub insert_result($self, $result) {
    my @cols = qw(type pos pid points event_id stage_id year);
    $self->_gen_insert('race_results', \@cols, $result);
}

sub insert_team($self, $team) {
    my @cols = qw(uid name mine year);
    $self->_gen_insert('teams', \@cols, $team);
}

sub insert_rider($self, $info) {
    my @cols = qw(pid name country country_long dob);
    croak "need pid"
        unless $info->{pid};
    if(!defined $info->{name}) {
        if(defined $info->{first_name} && defined $info->{last_name}) {
        $info->{name} = $info->{first_name}.' '.$info->{last_name}
    }
    else {
        $self->delete_rider_seen($info->{pid}, $self->year);
        return false;
    }
}
@cols = grep { exists $info->{$_} } @cols;
$self->_gen_insert('riders', \@cols, $info);
$self->set_rider_seen($info->{pid}, $self->year);
    return true;
}

sub set_rider_seen($self, $pid, $year=$self->year) {
    my $sth = $self->db->prepare(qq{INSERT OR REPLACE INTO riders_seen(pid, year) VALUES(?, ?)});
    $sth->execute($pid, $year);
}

sub insert_rider_price($self, $pid, $price, $year=$self->year) {
my $sth = $self->db->prepare(qq{
        INSERT OR REPLACE INTO rider_prices(pid, year, price) VALUES (?, ?, ?)
        });
    $sth->execute($pid, $year, $price);
}

sub delete_rider_seen($self, $pid, $year=$self->year) {
    my $sth = $self->db->prepare(qq{DELETE FROM riders_seen WHERE pid=? AND year=?});
    $sth->execute($pid, $year);
}


sub insert_uci_team ($self, $team) {
    my @cols = qw(name short cat year);
    $self->_gen_insert('uci_teams', \@cols, $team);
}

sub link_uci_team_rider($self, $short, $pid, $year=$self->year) {
    my $sth = $self->db->prepare(qq{
        INSERT OR REPLACE INTO uci_team_riders(year, pid, short) VALUES(?, ?, ?);
        });
    $sth->execute($year, $pid, $short);
}


has 'username' => (
    is => 'ro',
    default => 'h3kker',
);

has 'year' => (
    is => 'ro',
    lazy => true,
    default => sub {
        DateTime->now->year;
    },
);

has 'is_logged_in' => (
    is => 'rw',
    isa => 'Bool',
    default => false,
);

has 'base_url' => (
    is => 'ro',
    default => 'https://www.pdcvds.com'
);

has 'current_team_name' => (
    is => 'rw',
);
has 'current_uid' => (
    is => 'rw',
);

sub fetch_rider_list($self) {
    $self->login;
    my @riders;
    my $url = Mojo::URL->new($self->base_url.'/export.php')->query({ y => $self->year, mw => 1});
    my $res = $self->ua->get($url)->result;
    die 'Could not fetch export: '.$res->code
       unless $res->is_success;
    my ($fh, $tmpname) = tempfile;
    $res->save_to($tmpname);
    my $parser = Parse::CSV->new(
        file => $tmpname,
        names => true,
    );
    while(my $row = $parser->fetch) {
        push @riders, {
            pid => $row->{'rider id'},
            name => $row->{'rider name'},
            country => $row->{'country'},
            price => $row->{'price'},

        };
    }
    die $parser->errstr
        if $parser->errstr;

    return @riders;
}

sub fetch_rider_info($self, $pid, $year=$self->year) {
    die 'need pid' unless $pid;
    say "get info for ".$pid;
    my $date_parser = DateTime::Format::Strptime->new(
        pattern => '%d-%b-%Y',
        on_error => 'croak',
    );
        my $birthday_parser = DateTime::Format::Strptime->new(
            pattern => '%b %d, %Y',
            on_error => 'croak',

        );
    return $self->ua->get_p($self->base_url.'/riders.php?mw=1&y='.$year.'&pid='.$pid)
        ->then(sub($tx) {
            my $info = {
                year => $year,
                pid => $pid,
                uci_team => undef,
                price => undef,
                first_name => undef,
                last_name => undef,
                dob => undef,
                category => undef,
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

                if ($cols->[0]->text eq 'Team(s)' && $cols->[1]->text) {
                    $info->{teams} = $cols->[1]->text+0;
                }
                elsif ($cols->[0]->text eq 'First Name' && $cols->[1]->text) {
                    $info->{first_name} = $cols->[1]->text;
                    }
                elsif ($cols->[0]->text eq 'Last Name' && $cols->[1]->text) {
                    $info->{last_name} = $cols->[1]->text;
                }
                elsif ($cols->[0]->text eq 'Nationality') {
                    ($info->{country_long}, $info->{country}) = ($cols->[1]->at('a')->text =~ /\s*(.+) \((\w+)\)/);
                }
                elsif ($cols->[0]->text =~ /Salary/ && $cols->[1]->text ne '') {
                    $info->{price} = $cols->[1]->text+0;
                }
                elsif ($cols->[0]->text eq 'UCI Team' && $cols->[1]->at('a')->text) {
                    my ($team, $team_short) = ($cols->[1]->at('a')->text =~ /(.*) \((\w+)\)/);
                    $info->{uci_team} = _map_team($team)
                        if $team;
                    $info->{uci_team_short} = $team_short
                        if $team_short;
                }
                elsif($cols->[0]->text eq 'Birthday' && $cols->[1]->text) {
                    $info->{dob} = $birthday_parser->parse_datetime($cols->[1]->text)->ymd('-');
                }
                elsif($cols->[0]->text eq 'UCI Category') {
                    $info->{category} = $cols->[1]->text;
                }
            });
                return $info;
            })->catch(sub($err) {
                die 'could not fetch rider info for '.$pid.': '.$err;
        });
}

sub get_rider($self, $pid) {
    my $rider = $self->db->selectrow_hashref(q{SELECT * FROM riders WHERE pid=?}, undef, $pid);
}

sub get_race($self, $event_id, $year=$self->year) {
    my $race = $self->db->selectrow_hashref(q{SELECT * FROM races WHERE event_id=? AND year=?}, undef, $event_id, $year);
}

sub get_stages($self, $event_id, $year=$self->year) {
    $self->db->selectall_arrayref(q{SELECT * FROM stages WHERE event_id=? AND year=?}, {Slice => {}}, $event_id, $year);
}

sub get_team($self, $uid, $year=$self->year) {
    $self->db->selectrow_hashref(q{
    SELECT *, (
        SELECT count(*) FROM team_riders WHERE team_riders.uid=teams.uid AND team_riders.year=teams.year
        ) rider_count FROM teams WHERE uid=? AND year=?}, undef, $uid, $year);
}

sub remove_team_riders($self, $uid, $year=$self->year) {
    $self->db->do(q{
    DELETE FROM team_riders WHERE uid=? AND year=? }, undef, $uid, $year);
}

sub link_team_rider($self, $uid, $pid, $year=$self->year) {
    my $sth = $self->db->prepare(qq{
        INSERT OR REPLACE INTO team_riders(year, pid, uid) VALUES(?, ?, ?)
    });
    $sth->execute($year, $pid, $uid);

}

sub login($self) {
    return true 
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
    $self->is_logged_in(true);
}

sub fetch_teams($self) {
    my @teams;
    my $res = $self->ua->get($self->base_url.'/teams.php?mw=1&y='.$self->year)->result;
    die 'Could not fetch teams list: '.$res->code
        unless $res->is_success;
        my $page = $res->dom;
        my $rows = $page->at('div#content table')->children('tr')->tail(-1)->to_array;
    for my $row ($rows->@*) {
        my $cols = $row->children('td')->to_array;
        next unless scalar $cols->@*;
        my $team_url = Mojo::URL->new($cols->[2]->at('a')->attr('href'));
        my $team_name = $cols->[2]->at('a')->text;
        my $username = $cols->[1]->text;
        my $team_id = $team_url->query->param('uid');
        push @teams, {
            uid => $team_id,
            name => $team_name,
            mine => $username eq $self->username,
            year => $self->year,
        };
    }
    return \@teams;
}
sub fetch_riders_for_team($self, $team) {
    $self->login;
    say "get team...".$team;
    return $self->ua->get_p($self->base_url.'/teams.php?mw=1&y='.$self->year.'&uid='.$team)->then(sub($tx) {
        my $res = $tx->result;
    die 'Could not fetch team'.$team.': '.$res->code
        unless $res->is_success;
    
    my $page = $res->dom;
    my $rows = $page->at('div#content table')->children('tr');
    my $riders = $rows->tail(-1)->head(-1)->map(sub($row) {
        my $cols = $row->children('td')->to_array;
        my $rider_url = Mojo::URL->new($cols->[4]->at('a')->attr('href'));
        my $rider_id = $rider_url->query->param('pid');
        return $rider_id;
    });
    return $riders->to_array;
    });
}

sub _map_name($name) {
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

sub _map_team($team) {
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

sub fetch_race_list($self) {
    my $res = $self->ua->get($self->base_url.'/results.php?mw=1&y='.$self->year)->result;
    die 'Could not fetch results: '.$res->code
        unless $res->is_success;
    my $races = $res->dom->at('div#content table.noevents')->children('tr')->tail(-1)->head(-1)->map(sub ($row) {
        my $race = {
            type => undef,
            name => undef,
            event_id => undef,
            country => undef,
            year => $self->year,
        };
        my $tds = $row->find('td')->to_array;
        my $links = $tds->[4]->find('a')->to_array;
        $race->{event_id} = Mojo::URL->new($links->[0]->attr('href'))->query->param('event');
        $race->{country} = Mojo::URL->new($tds->[2]->at('a')->attr('href'))->query->param('country');
        $race->{country_long} = $tds->[2]->at('a')->attr('title');
        $race->{name} = $links->[0]->text;
        if ($links->@* == 2) {
            $race->{type} = 'stage_race';
            $race->{stage_id} = Mojo::URL->new($links->[1]->attr('href'))->query->param('race');
            $race->{num} = _parse_stage_text($links->[1]->text);
        }
        else {
            $race->{type} = 'single_day_race';
        }
        return $race;
    });
    my %races;
    for my $race ($races->@*) {
        $races{$race->{event_id}} //= { $race->%* };
        if ($race->{type} eq 'stage_race') {
            $races{$race->{event_id}}->{stages} //= [];
            push $races{$race->{event_id}}->{stages}->@*, $race;
        }
    }
    return [values %races ];
}

sub _parse_race_date($date_str) {
    my $date_parser = DateTime::Format::Strptime->new(
        pattern => '%d-%b-%Y',
        on_error => 'croak',
    );

    if ($date_str =~ /, (\w+) (\d+), (\d+)/) {
        return $date_parser->parse_datetime(sprintf "%d-%s-%d" => $2, $1, $3)->ymd('-');
    }
    else {
        die 'Unable to parse date: '.$date_str;
    }

}

sub _parse_stage_text($text) {
    # format is [order].Stage [num]
    if ($text =~ m/(Stage|Prologue)\s*([\dab]*)/) {
        return $1 eq 'Stage' ? $2 : '00-'.$1;
    }
    else {
        warn 'cannot parse stage: '. $text;
        return 0;
    }
}

my %type_map = (
    'Single-day race' => 'single_day_race',
    'Stage race' => 'stage_race',
);


sub fetch_race($self, $event_id) {
    my $race_url = Mojo::URL->new($self->base_url.'/results.php')->query({ mw => 1, y=> $self->year, event => $event_id});
    say "fetch $race_url";
    my $res = $self->ua->get($race_url)->result;
    die 'Could not fetch race '.$race_url.': '.$res->code
        unless $res->is_success;
        my ($title) = $res->dom->at('h2')->text =~/Results :: (.*)/;
        my $race_info = { year => $self->year, event_id => $event_id, name => $title };
        $res->dom->find('h2')->first(sub($e) { $e->text =~ /^Results/ })
            ->following('table.noevents')->first->find('tr')->tail(-1)->each(sub ($row, $n) {
                my $tds = $row->find('td')->to_array;
                my $row_info = lc $tds->[0]->text;
                if ($row_info eq 'type') {
                    $race_info->{type} = $type_map{$tds->[1]->text} //
                        die 'unknown type '.$tds->[1]->text;
                }
                elsif($row_info eq 'category') {
                    $race_info->{cat} = Mojo::URL->new($tds->[1]->at('a')->attr('href'))->query->param('cat');
                }
                elsif($row_info eq 'date' || $row_info eq 'first stage') {
                    $race_info->{start_date} = _parse_race_date($tds->[1]->text);
                }
                elsif($row_info eq 'last stage') {
                    $race_info->{end_date} = _parse_race_date($tds->[1]->text);
                }
                elsif($row_info eq 'country') {
                    $race_info->{country} = Mojo::URL->new($tds->[1]->at('a')->attr('href'))->query->param('country');
                }

            });
        if ($race_info->{type} eq 'single_day_race') {
        $race_info->{end_date} = $race_info->{start_date}
        }
        else {
            # must be overview page
            # stage table is the 2nd one
                # not a stage table after all?
                # see https://www.pdcvds.com/results.php?mw=1&y=2024&event=39
            my $stage_table = $res->dom->find('table.noevents')->to_array->[1] ||
                die('no stage table? at '.$race_url);
            $race_info->{stages} = [];
            my $peek_first = $stage_table->find('tr')->tail(-1)->first;
            return $race_info if $peek_first->find('th')->first;
            # no stages?
            # see https://pdcvds.com/results.php?mw=1&y=2024&event=39
            $stage_table->find('tr')->tail(-1)->each(sub ($row, $n) {
                my $stage_info = {
                    event_id => $event_id, year => $self->year,
                };
                my $tds = $row->find('td')->to_array;
                my $stage_link = $tds->[1]->at('a');
                if ($stage_link) {
                    $stage_info->{num} = _parse_stage_text($stage_link->text);
                    $stage_info->{date} = _parse_race_date($tds->[0]->text.', '.$self->year);
                    $stage_info->{stage_id} = Mojo::URL->new($stage_link->attr('href'))->query->param('race');
                }
                else {
                # only a link when there's a result
                # no race_id though
                    $stage_info->{num} = _parse_stage_text($tds->[1]->text);
                }

            push $race_info->{stages}->@*, $stage_info;
        });
    }
    return $race_info;
}

sub fetch_results($self, $race) {
    my $_do_fetch = sub($url) {
        return $self->ua->get_p($url)->then(sub($tx) {
            my $res = $tx->result;
            die sprintf('Could not fetch results from %s %s: %s' => $url, $res->code, $res->message)
                unless $res->is_success;
            return $res;

        })->catch(sub($ex) {
            die 'fetch fail '.$ex;
        });
    };
    my $parse_result_row = sub($row, $type) {
        my $tds = $row->find('td')->to_array;
        die 'no td? in '.$row
            unless $tds->@*;
        my $pos = $tds->[0]->text;
        $pos =~ tr/\. //d;
        return {
            pos => $pos+0,
            pid => Mojo::URL->new($tds->[3]->at('a')->attr('href'))->query->param('pid'),
            name => _map_name($tds->[3]->at('a')->text),
            points => $tds->[4]->text+0,
            type => $type,
            year => $self->year,
        };
    };
    my $url = Mojo::URL->new($self->base_url.'/results.php')->query({ mw => 1, y=> $self->year});
    if ($race->{stage_id}) {
        $url->query->merge(race => $race->{stage_id});
        return $_do_fetch->($url)->then(sub($res) {
            my $head = $res->dom->find('h3')->first(sub($e) { $e->text =~ /^Stage/ });
            die 'no results at '.$url
                unless $head;
            my $state = 'stage';
        my $results = [];
            $head->following('table.noevents')->first->find('tr')->each(sub($row, $n) {
                my $heads = $row->find('th')->to_array;
                if (scalar $heads->@* == 2) {
                    if ($heads->[1]->text =~ /^Placing/) {
                        $state = 'stage';
                    }
                    elsif ($heads->[1]->text =~ /^Intermediate/) {
                        $state = 'jersey';
                    }
                    elsif ($heads->[1]->text =~ /Final leader/) {
                        $state = 'gc';
                    }
                    elsif ($heads->[1]->text =~ /Final .* jersey/) {
                        $state = 'jersey';
                    }
                    else {
                        die 'Unexpected: '.$heads->[1]->text.' on '.$url;
                    }
                }
                else {
                return unless $row->find('td')->size > 1;
                    push $results->@*, $parse_result_row->($row, $state)
                }
            });
        return $results;
        });
    }
    elsif ($race->{event_id}) {
        $url->query->merge(event => $race->{event_id});
        return $_do_fetch->($url)->then(sub($res) {
            my $results_table = $res->dom->find('h3')->first(sub($e) { $e->text eq 'Results'})->following('table.noevents')->first;
            die 'no result for '.$url
                unless $results_table;
            return $results_table->find('tr')->tail(-1)->head(-1)->map(sub ($row) {
                $parse_result_row->($row, 'single_day_race');
            })->to_array;
        });
    }
    else {
        die 'need stage_id or event_id';
    }
}

true;