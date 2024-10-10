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
        my $dbh =  DBI->connect("dbi:SQLite:dbname=pdcvds.db","","");
        $dbh->{AutoCommit} = 1;
        $dbh;
    }
);
has 'insert_race_sth' => (
    is => 'ro',
    lazy => true,
    default => sub($self) {
    $self->db->prepare(qq{
        INSERT OR REPLACE INTO races(event, name, type,country) VALUES (?, ?, ?, ?)
    });
    }
);
has 'set_race_date_sth' => (
    is => 'ro',
    lazy => true,
    default => sub($self) {
        $self->db->prepare(qq{
                UPDATE races SET start_date = ?, end_date = ? WHERE event = ?

        });
    }
);
has 'set_race_type_sth' => (
    is => 'ro',
    lazy => true,
    default => sub($self) {
        $self->db->prepare(qq{
                UPDATE races SET type = ? WHERE event = ?

        });
    }
);
has 'insert_stage_sth' => (
    is => 'ro',
    lazy => true,
    default => sub($self) {
        $self->db->prepare(qq{
        INSERT OR REPLACE INTO stages(race, stage, num, date) VALUES (?, ?, ?,?)
        });
    }

);
has 'insert_result_sth' => (
    is => 'ro',
    lazy => true,
    default => sub($self){
        $self->db->prepare(qq{
        INSERT OR REPLACE INTO results(type, pos, pid, points, event, stage) VALUES(?, ?, ?, ?, ?, ?)
        });
    }

);
has 'insert_rider_basic_sth' => (
    is => 'ro',
    lazy => true,
    default => sub($self) {
        $self->db->prepare(qq{
        INSERT OR REPLACE INTO riders(pid, name, country) VALUES(?, ?, ?) 
        });
    }
);
has 'insert_price_sth' => (
    is => 'ro',
    lazy => true,
    default => sub($self){
        $self->db->prepare(qq{
        INSERT OR REPLACE INTO rider_prices(pid, year, price) VALUES (?, ?, ?)
        });
    }
);
    has 'insert_uci_team_sth' => (
        is => 'ro',
        lazy => true,
        default => sub($self) {
    $self->db->prepare(qq{
        INSERT OR REPLACE INTO uci_teams(name, short, cat, year) VALUES(?, ?, ?, ?)
        });
    }

);
has 'insert_uci_team_riders_sth' => (
    is => 'ro',
    lazy => true,
    default => sub($self) {
        $self->db->prepare(qq{
        INSERT OR REPLACE INTO uci_team_riders(year, pid, short) VALUES(?, ?, ?);

        });

    }

);
has 'insert_rider_sth' => (
    is => 'ro',
    lazy => true,
    default => sub($self) {
        $self->db->prepare(qq{
        INSERT OR REPLACE INTO riders(pid, name, country, country_long, dob) VALUES(?, ?, ?, ?, ?) 
        });
    }
);
has 'set_rider_seen_sth' => (
    is => 'ro',
    lazy => true,
    default => sub($self) {
        $self->db->prepare(qq{
            INSERT OR REPLACE INTO riders_seen(pid, year) VALUES(?, ?)});
    }
);
has 'delete_rider_seen_sth' => (
    is => 'ro',
    lazy => true,
    default => sub($self) {
        $self->db->prepare(qq{
            DELETE FROM riders_seen WHERE pid=? AND year=?});
    }
);

sub insert_rider($self, $info) {
    croak "need pid"
        unless $info->{pid};
    if(!defined $info->{name}) {
        if(defined $info->{first_name} && defined $info->{last_name}) {
        $info->{name} = $info->{first_name}.' '.$info->{last_name}
    }
    else {
        $self->delete_rider_seen_sth->execute($info->{pid}, $self->year);
        return false;
    }
}
    $self->insert_rider_sth->execute($info->{pid}, $info->{name}, $info->{country}, $info->{country_long}, $info->{dob});
    $self->set_rider_seen_sth->execute($info->{pid}, $self->year);
    return true;
}

    has 'insert_uci_team_sth' => (
        is => 'ro',
        lazy => true,
        default => sub($self) {
    $self->db->prepare(qq{
    INSERT OR REPLACE INTO uci_teams(name, short, cat, year) VALUES(?, ?, ?, ?);
    });
        }
);
sub insert_uci_team ($self, $name, $short, $cat, $year) {
    $self->insert_uci_team_sth->execute($name, $short, $cat, $year);

}

has 'insert_uci_team_riders_sth' => (
    is => 'ro',
    lazy => true,
    default => sub($self) {
        $self->db->prepare(qq{
        INSERT OR REPLACE INTO uci_team_riders(year, pid, short) VALUES(?, ?, ?);
        });
    }
);
sub insert_uci_team_rider($self, $year, $pid, $short) {
    $self->insert_uci_team_riders_sth->execute($year, $pid, $short);
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

sub get_rider_list($self) {
    $self->login;
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
    while(my $info = $parser->fetch) {
        $self->insert_rider_basic_sth->execute($info->{'rider id'}, $info->{'rider name'}, $info->{'country'})
            || die 'insert '.$info->{'rider id'};
        $self->set_rider_seen_sth->execute($info->{'rider id'}, $self->year);
        $self->insert_price_sth->execute($info->{'rider id'}, $self->year, $info->{price});
    }
    die $parser->errstr
        if $parser->errstr;
}

sub get_rider_info($self, $pid, $year=$self->year) {
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
                    $info->{dob} = $birthday_parser->parse_datetime($cols->[1]->text)->iso8601;
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

true;