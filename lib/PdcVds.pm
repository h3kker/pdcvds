package PdcVds;

use v5.36;

use Mojo::File;
use Mojo::UserAgent;
use Mojo::JSON qw(decode_json encode_json);
use Mojo::URL;
use Mojo::Promise;
use DateTime;
use DateTime::Format::Strptime;
use DBI;


use open ':std', ':encoding(UTF-8)';
use utf8;

use feature 'try';
use Moose;

has 'ua' => (
    lazy => 1,
    is => 'ro',
    default => sub {
        my $ua = Mojo::UserAgent->new;
        $ua->connect_timeout(10);
        $ua;
    }
);
has 'db' => (
    is => 'ro',
    lazy => 1,
    default => sub {
        my $dbh =  DBI->connect("dbi:SQLite:dbname=pdcvds.db","","");
        $dbh->{AutoCommit} = 1;
        $dbh;
    }
);
has 'insert_race_sth' => (
    is => 'ro',
    lazy => 1,
    default => sub($self) {
    $self->db->prepare(qq{
        INSERT OR REPLACE INTO races(event, name, type,country) VALUES (?, ?, ?, ?)
    });
    }
);
has 'set_race_date_sth' => (
    is => 'ro',
    lazy => 1,
    default => sub($self) {
        $self->db->prepare(qq{
                UPDATE races SET start_date = ?, end_date = ? WHERE event = ?

        });
    }
);
has 'set_race_type_sth' => (
    is => 'ro',
    lazy => 1,
    default => sub($self) {
        $self->db->prepare(qq{
                UPDATE races SET type = ? WHERE event = ?

        });
    }
);
has 'insert_stage_sth' => (
    is => 'ro',
    lazy => 1,
    default => sub($self) {
        $self->db->prepare(qq{
        INSERT OR REPLACE INTO stages(race, stage, num, date) VALUES (?, ?, ?,?)
        });
    }

);
has 'insert_result_sth' => (
    is => 'ro',
    lazy => 1,
    default => sub($self){
        $self->db->prepare(qq{
        INSERT OR REPLACE INTO results(type, pos, pid, points, event, stage) VALUES(?, ?, ?, ?, ?, ?)
        });
    }

);
has 'insert_rider_sth' => (
    is => 'ro',
    lazy => 1,
    default => sub($self){
        $self->db->prepare(qq{
        INSERT OR REPLACE INTO riders(pid, name, nationality, dob) VALUES(?, ?, ?, ?) 
        });
    }

);
has 'insert_price_sth' => (
    is => 'ro',
    lazy => 1,
    default => sub($self){
        $self->db->prepare(qq{
        INSERT OR REPLACE INTO rider_prices(pid, year, price) VALUES (?, ?, ?)
        });
    }
);
    has 'insert_uci_team_sth' => (
        is => 'ro',
        lazy => 1,
        default => sub($self) {
    $self->db->prepare(qq{

    INSERT OR REPLACE INTO uci_teams(name, short, cat, year) VALUES(?, ?, ?, ?);
    });

        }

);
has 'insert_uci_team_riders_sth' => (
    is => 'ro',
    lazy => 1,
    default => sub($self) {
        $self->db->prepare(qq{
        INSERT OR REPLACE INTO uci_team_riders(year, pid, short) VALUES(?, ?, ?);

        });

    }

);
has 'update_born_sth' => (
    is => 'ro',
    lazy => 1,
    default => sub($self) {
        $self->db->prepare(qq{
            UPDATE riders set born=? WHERE pid=?

        });
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

sub get_current_team($self) {
my $cur = $self->db->selectrow_arrayref("SELECT uid, name FROM teams WHERE year=? AND mine", undef, $self->year);
    die(" No team for". $self->year) unless defined $cur;
    $self->current_team_name($cur->[1]);
    $self->current_uid($cur->[0]);

}

has 'current_team_name' => (
    is => 'rw',
);
has 'current_uid' => (
is => 'rw',
);

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
sub get_rider_list($self, $page=0) {
    $self->login;
    my $url = Mojo::URL->new($self->base_url.'/riders.php')->query({ year => $self->year, mw => 1, n => 0});
    $url = $url->query({p => $page, n=> undef })
        if $page;
    say "get rider list: ".$url;

    my $res = $self->ua->get($url)->result;
    die 'could not fetch rider list:'.$res->code
        unless $res->is_success;
        my @riders;
        my $page_dom = $res->dom;
        my $next_page;
        my $nav = $page_dom->at('div.nav');
        if ($nav) {
        for my $nav_link($page_dom->at('div.nav')->find('a')->each) {
            if ($nav_link->text eq 'next›') {
                $next_page = Mojo::URL->new($nav_link->attr('href'))->query->param('p');

        }

}
$self->get_rider_list($next_page) if $next_page;
}
    my $rows = $page_dom->at('div#content table.cell')->children('tr');
    $rows->tail(-1)->head(-1)->each(sub($row, $n) {
        my $cols = $row->children('td')->to_array;
        my $country = Mojo::URL->new($cols->[1]->at('a')->attr('href'))->query->param('nat');
        my $team = Mojo::URL->new($cols->[2]->at('a')->attr('href'))->query->param('uci');
        my $class = $cols->[3]->all_text || '-';
        my $rider_el = $cols->[4]->at('a');
        my $born = $cols->[5]->text +0;

        my $rider_id = Mojo::URL->new($rider_el->attr('href'))->query->param('pid');
        my $rider_name = $rider_el->text;
        say "$rider_name:$rider_id:$country:$team:$class: $born";
        $self->insert_uci_team_sth->execute($team, $team, $class, $self->year);
        $self->insert_uci_team_riders_sth->execute($self->year, $rider_id, $team);
        $self->update_born_sth->execute($born, $rider_id,);

    });
}

sub get_riders_for_team($self, $team) {
    $self->login;
    say "get team...".$team;
    my $res = $self->ua->get($self->base_url.'/teams.php?mw=1&y='.$self->year.'&uid='.$team)->result;
    die 'Could not fetch team'.$team.': '.$res->code
        unless $res->is_success;
    
    my $now = DateTime->now;

    my @riders;
    my @results;

    my $page = $res->dom;
    my @to_fetch;
    my $rows = $page->at('div#content table')->children('tr');
    $rows->tail(-1)->head(-1)->each(sub($row, $n) {
        my $cols = $row->children('td')->to_array;
        my $team = $cols->[2]->at('a')->attr('title');
        $team = _map_team($team);
        my $rider_url = Mojo::URL->new($cols->[4]->at('a')->attr('href'));
        my $rider_id = $rider_url->query->param('pid');
        my $base_info = {
            pid => $rider_id,
            country => $cols->[1]->at('img')->attr('alt'),
            team_short => $cols->[2]->at('a')->text,
            team => $team,
            cat => $cols->[3]->all_text,
            name => _map_name($cols->[4]->at('a')->text),
        };
        my $have = $self->get_rider($rider_id);
        unless($have) {
            say "$rider_id not in db";
            push @to_fetch, $base_info;
            
        }
        else {
            say "$rider_id already in db";
            push @riders, $have;
        }
        });
            say "fetch ".scalar @to_fetch." riders";

        my $p = Mojo::Promise->map({ concurrency => 2}, sub($base_info) {
            $self->get_rider_info($base_info->{pid})->then(sub($info) {
                say "got rider info from pdcvds for ".$base_info->{name};
                for my $f (qw{dob price}) {
                    $base_info->{$f} = $info->{$f};

            }
    use Data::Dumper; say Dumper $base_info;
            $self->insert_rider_sth->execute($base_info->{pid}, $base_info->{name}, $base_info->{country}, $base_info->{dob});
            $self->insert_price_sth->execute($base_info->{pid}, $self->year, $base_info->{price});
            push @riders, $base_info;
            $base_info;


        });
        }, @to_fetch) if scalar @to_fetch;
    \@riders;
}

sub get_rider_info($self, $pid, $year=$self->year) {
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
                teams => undef,
                team => undef,
                team_short => undef,
                price => undef,
                dob => undef,
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
                    $info->{team} = _map_team($team)
                        if $team;
                    $info->{team_short} = $team_short
                        if $team_short;
                }
                elsif($cols->[0]->text eq 'Birthday' && $cols->[1]->text ne '') {
                    $info->{dob} = $birthday_parser->parse_datetime($cols->[1]->text)->iso8601;

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
sub get_rider($self, $pid) {
my $rider = $self->db->selectrow_hashref(qq{
        SELECT pid, dob, name, nationality, spec_gc, spec_oneday, spec_tt, spec_climber, spec_sprint FROM riders WHERE pid=?
        AND EXISTS (SELECT * FROM rider_prices rp where rp.pid=riders.pid and rp.year=?)
        }, undef, $pid, $self->year);
$rider;
}
sub get_teams($self) {
        my $team_riders_sth = $self->db->prepare(qq{
            INSERT OR REPLACE INTO team_riders(year, pid, uid) VALUES(?, ?, ?)
        }) or die("prepare team_rider stmt");
    $self->login;
    my $team_sth = $self->db->prepare(qq{
        INSERT OR REPLACE INTO teams (uid, name, mine, year) VALUES(?, ?, ?, ?) 
        });
    say "get teams...";
    my $team_count = 0;

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
        say  "$team_name:$team_id";
        $team_count++;
            $team_sth->execute($team_id, $team_name, $username eq $self->username, $self->year);

        my $riders = $self->get_riders_for_team($team_id);
            say " got ".scalar $riders->@*." riders";
            for my $rider($riders->@*) {
                say "link team rider".$rider->{pid}."+".$team_id;
                $team_riders_sth->execute($self->year, $rider->{pid}, $team_id);

            }
    } 
    
say "got $team_count teams";
}

sub get_results_list($self) {
    my $res = $self->ua->get($self->base_url.'/results.php?mw=1&y='.$self->year)->result;
    die 'Could not fetch results: '.$res->code
        unless $res->is_success;
    $res->dom->at('div#content table.noevents')->children('tr')->tail(-1)->head(-1)->map(sub ($row) {
        my $tds = $row->find('td')->to_array;
        my $links = $tds->[4]->find('a')->to_array;
    my ($type, $stage_id, $stage_num);

        my $id = Mojo::URL->new($links->[0]->attr('href'))->query->param('event');
        my $country = Mojo::URL->new($tds->[2]->at('a')->attr('href'))->query->param('country');
        my $name = $links->[0]->text;
        if ($links->@* == 2) {
            $type = 'Stage race';
            $stage_id = Mojo::URL->new($links->[1]->attr('href'))->query->param('race');
        if ($links->[1]->text =~ m/(\d)\. Stage/) {
            $stage_num = $1;
        }
        }
        else {
            $type = 'Single-day race';

        }
        $self->insert_race_sth->execute($id, $name, $type, $country);
        $self->insert_stage_sth->execute($id, $stage_id, $stage_num, undef);
});
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
        die 'Unable to parse date: '.$date_str->text;
    }

}
sub get_race($self, $event_id) {
    my $race_url = Mojo::URL->new($self->base_url.'/results.php')->query({ mw => 1, y=> $self->year, event => $event_id});
    my $res = $self->ua->get($race_url)->result;
    die 'Could not fetch race '.$race_url.': '.$res->code
        unless $res->is_success;
        my $race_info;
        $res->dom->find('h2')->first(sub($e) { $e->text =~ /^Results/ })
            ->following('table.noevents')->first->find('tr')->tail(-1)->each(sub ($row, $n) {
                my $tds = $row->find('td')->to_array;
                if ($tds->[0]->text eq 'Type') {
                    $race_info->{type} = $tds->[1]->text;
                }

            });

    $race_info;
}

sub race_info($self, $race_info) {
    my $race_url = Mojo::URL->new($self->base_url.'/results.php')->query({ mw => 1, y => $self->year})->query($race_info);
    my $res = $self->ua->get($race_url)->result;
    die 'Could not fetch race '.$race_url.': '.$res->code
        unless $res->is_success;
        my $tbl_rows = $res->dom->find('h2')->first(sub($e) { $e->text =~/^Results/ })
            ->following('table.noevents')->first->find('tr')->tail(-1);
            $tbl_rows->each(sub($row, $n) {
                my $tds = $row->find('td')->to_array;
                if ($tds->[0]->text eq 'Type') {
                    $race_info->{type} = $tds->[1]->text;
                }
                # stage race
                elsif ($tds->[0]->text eq 'First stage') {
                    $race_info->{start_date} = _parse_race_date($tds->[1]->text);
                }
                 # single day
                elsif($tds->[0]->text eq 'Date') {
                    $race_info->{start_date} = _parse_race_date($tds->[1]->text);
                    $race_info->{end_date} = $race_info->{start_date};
                }
                elsif ($tds->[0]->text eq 'Last stage') {
                    $race_info->{end_date} = _parse_race_date($tds->[1]->text);
                }

            });

    $self->set_race_date_sth->execute($race_info->{start_date}, $race_info->{end_date}, $race_info->{event});
    $self->set_race_type_sth->execute($race_info->{type}, $race_info->{event});
    my $parse_result_row = sub($row, $type) {
        my $tds = $row->find('td')->to_array;
        my $pos = $tds->[0]->text;
        $pos =~ tr/\. //d;
        return {
            rank => $pos+0,
            pid => Mojo::URL->new($tds->[3]->at('a')->attr('href'))->query->param('pid'),
            name => _map_name($tds->[3]->at('a')->text),
            points => $tds->[4]->text+0,
            type => $type,
        };
    };
    
    if ($race_info->{type} eq 'Single-day race') {
        $race_info->{results} = { final => $res->dom->find('h3')->first(sub($e) { $e->text eq 'Results'})
            ->following('table.noevents')->first->find('tr')->tail(-1)->head(-1)->map(sub ($row) {
                $parse_result_row->($row, 'oneday');
            })->to_array };
        return $race_info;
    }
    else {
        my $head = $res->dom->find('h3')->first(sub($e) { $e->text =~ /^Stage/ });
        $race_info->{results} = {};
        unless ($head) {
            # must be overview page
            my $stage_table = $res->dom->find('table.noevents')->to_array->[1];
            $race_info->{results}{stages} = [];
            $stage_table->find('tr')->tail(-1)->each(sub ($row, $n) {
                my $tds = $row->find('td')->to_array;
                my $stage_link = $tds->[1]->at('a');
                return unless $stage_link;

                my $date = _parse_race_date($tds->[0]->text.', '.$self->year);
                my ($num, $stage_name) = ($stage_link->text =~ /^(\d+)\. (.+)/);
                my $stage_id = Mojo::URL->new($stage_link->attr('href'))->query->param('race');
                my $results = $self->race_info({ race => $stage_id });
                push $race_info->{results}{stages}->@*, {
                    stage_date => $date,
                    stage => $num,
                    name => $stage_name,
                    gc => $results->{gc},
                    result => $results->{result},
                   jerseys => $results->{jersey},
                };
            });
            $race_info->{results}{final} = $race_info->{results}{stages}[-1]{gc};
            $race_info->{results}{final_jerseys} = $race_info->{results}{stages}[-1]{jerseys};
            return $race_info;
        }

        my $state;
        my $results = {
            result => [],
            jersey => [],
            gc => [],
        };
        $head->following('table.noevents')->first->find('tr')->each(sub($row, $n) {
            my $heads = $row->find('th')->to_array;
            if (scalar $heads->@* == 2) {
                if ($heads->[1]->text =~ /^Placing/) {
                    $state = 'result';
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
                    die 'Unexpected: '.$heads->[1]->text.' on '.$race_info->{link};
                }
                return;
            }
            return if (($row->attr('class')//'') eq 'lite') ||
                $row->find('td')->size == 1;
            
            push $results->{$state}->@*, $parse_result_row->($row, $state);
        });
        return $results;
    }
    

    

}
1;
