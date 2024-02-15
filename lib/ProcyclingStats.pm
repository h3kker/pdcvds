package ProcyclingStats;

use v5.36;

use Mojo::UserAgent;
use Mojo::JSON qw(encode_json decode_json);
use Mojo::File;
use Mojo::Util qw(slugify);
use Mojo::URL;
use DateTime;
use utf8;

use Moose;

use feature 'try';

has 'ua' => (
    is => 'ro',
    default => sub {
        Mojo::UserAgent->new;
    }
);

has 'base_url' => (
    is => 'ro',
    default => 'https://www.procyclingstats.com',
);

sub _get_date($d) {
    my @p = split '\.', $d;
    DateTime->new(
        year => DateTime->now->year,
        month => $p[1],
        day => $p[0],
    );
}

sub available_results($self) {
    my $res = $self->ua->get($self->base_url.'/races.php?category=1&filter=Filter&s=latest-results')->result;
    die 'Unable to fetch: '.$res->code
        unless $res->is_success;
    my $rows = $res->dom->at('.table-cont table tbody')->find('tr');
    my %available;
    $rows->each(sub($row, $n) {
        my $cols = $row->find('td')->to_array;
        my ($type, $class) = split '\.', $cols->[2]->text;
        return unless $class && (
                $class eq 'UWT'
                || $class eq '1'
                || $class eq 'Pro'
            );

        my ($name, $stage) = split ' \| ', $cols->[1]->at('a')->text;
        return if $available{$name};
        my $link = $cols->[1]->at('a')->attr('href');
        say "fetch info for $name from $link";
        $link =~ s,/[^/]+?$,/overview,;
        $available{$name} = $self->race_info($self->base_url.'/'.$link);
    });
    return [ values %available ];
}

sub upcoming($self) {
    my $next_week = DateTime->now->add(weeks => 2);
    
    my $res = $self->ua->get($self->base_url.'/races.php?popular=pro_me&s=upcoming-races')->result;
    die 'Unable to fetch: '.$res->code
        unless $res->is_success;
    my $rows = $res->dom->at('.table-cont table tbody')->find('tr');
    my @races;
    $rows->each(sub($r, $n) {
        my $cols = $r->find('td')->to_array;
        my @date = split ' - ', $cols->[0]->text;
        my $start = _get_date($date[0]);
        return
            if ($start > $next_week);
        
        push @races, {
            race => $cols->[1]->at('a')->text,
            link => $self->base_url.'/'.$cols->[1]->at('a')->attr('href'),
        };
    });
    return \@races;
}

sub search_rider($self, $name) {
    my $search_url = Mojo::URL->new($self->base_url.'/resources/search.php')
        ->query(term => $name);

    my $res = $self->ua->get($search_url)->result;
    die 'Unable to fetch: '.$res->code
        unless $res->is_success;
    my @rows = grep { $_->{page} eq 'rider' } $res->json->@*;
    if (scalar @rows == 0) {
        die 'no result found for '.$name;
    }
    return $rows[0];
}

sub rider_specialties($self, $name) {
    my $rider = $self->search_rider($name);

    my $res = $self->ua->get($self->base_url.'/rider/'.$rider->{id})->result;
    die 'Unable to fetch: '.$res->code
        unless $res->is_success;
    if (my $hdr = $res->dom->at('div.main h1')) {
        die 'Rider '.$name.' ('.$rider->{id}.') not found'
            if $hdr->text eq 'Page not found';
    }
    
    my $cats = {};
    my $pps = $res->dom->at('div.pps ul');
    unless ($pps) {
        die 'could not find pps for '.$name;
    }
    $pps->find('li')->each(sub($li, $n) {
        my $spec_name = $li->at('div.title a')->text;
        $cats->{$spec_name} = $li->at('div.pnt')->text + 0;
    });
    return $cats;
}

sub race_info($self, $race_url) {
    my $ov_res = $self->ua->get($race_url)->result;
    die 'Unable to fetch: '.$ov_res->code
        unless $ov_res->is_success;
    
    my $info_list = $ov_res->dom->at('ul.infolist');
    unless ($info_list) {
        die 'Check out '.$race_url.' - no infos?';
    }
    
    my $infos = $info_list->find('li')->to_array;
    return {
        start_date => $infos->[0]->find('div')->last->text,
        end_date => $infos->[1]->find('div')->last->text,
        race => $ov_res->dom->at('div.main h1')->text,
        link => $race_url,
    }
}

sub race_info_stages($self, $race_url) {
say $race_url;
    my ($year) = ($race_url =~ m,/(\d{4})/,);
    my $ov_res = $self->ua->get($race_url)->result;
    die 'Unable to fetch: '.$ov_res->code
        unless $ov_res->is_success;
    my $stages_head = $ov_res->dom->at('div.content')->find('h3')->first(sub($h) {
        $h->text eq 'Stages'
    });
    return undef
        unless $stages_head;

    my $stages = [];
    $stages_head->following('.table-cont')->first->find('tr')->each(sub($st, $n) {
        my $stage_info = $st->find('td')->to_array;
        return unless scalar $stage_info->@*;
        my ($d, $m) = (split '/', $stage_info->[0]->text);
        my ($num, $name) = (split ' to ', $stage_info->[3]->at('a')->text);
        $num =~ s/Stage //i;
        #my $len = $stage_info->[4]->text =~ /(\d+)/ ? $1 : undef;

        push $stages->@*, {
            stage_date => sprintf('%4d-%02d-%02d' => $year, $m, $d),
            num => $n,
            stage => $num,
            name => $name,
            length => -1,
            link => $self->base_url.'/'.$stage_info->[3]->at('a')->attr('href'),
        }
    });
    return $stages;
}

sub start_list($self, $race_url) {
    my $start_url = $race_url;
    $start_url =~ s,/overview$,,;
    $start_url .= '/startlist';

    my $res = $self->ua->get($start_url.'/top-competitors')->result;
    die 'Unable to fetch: '.$res->code 
        unless $res->is_success;
    
    my $list = $res->dom->at('div.content table.basic tbody')->find('tr');
    return $list->map(sub($row) {
        my $cols = $row->find('td')->to_array;
        my $rank = $cols->[0]->text;
        my $name = $cols->[1]->at('a')->all_text;
        return {
            # force name to title case
            name => _transform_name($name),
            team => $cols->[2]->at('a')->text,
            rank => $rank + 0,
        };
    });
}

sub _transform_name($name) {
    # ranked table uses css to uppercase lastname, elsewhere
    # it is hard uppercase.
    $name =~ /^([\p{Word}\-' ]+) (.+)$/;
    die "$name does not match"
        unless $1 && $2;
    sprintf("%s %s" => $2, join('', map { ucfirst(lc $_) } split "([ '-])", $1));
}

sub results($self, $race_url) {
    my $stages = $self->race_info_stages($race_url);
    unless ($stages) {
        my $results_url = $race_url;
        $results_url =~ s,/overview,/result,;
        return $self->results_oneday($results_url);
    }
    
    my $results = {
        final => [],
        stages => [],
    };
    for my $stage (sort { $a->{num} <=> $b->{num} } $stages->@*) {
        my $ttt = ($stage->{stage} =~ /TTT/) ? 1 : 0;
        say "fetch stage ".$stage->{stage};
        say " (team time trial, gc only)"
            if $ttt;
        my $res = $self->results_stage($stage->{link}, $ttt);
        $stage->{result} = $res->{stage};
        $stage->{gc} = $res->{gc};
        push $results->{stages}->@*, $stage;
    }
    say $race_url;
    $results->{final} = $results->{stages}->[-1]->{gc};
    $results;
}

sub results_oneday($self, $results_url) {
    my $res = $self->ua->get($results_url)->result;
    die 'Unable to fetch: '.$res->code
        unless $res->is_success;

    return {
        final => _parse_result_rows(
            $res->dom->at('div.content table.results'))->to_array,
    }
}

sub results_stage($self, $results_url, $ttt=0) {
    my $res = $self->ua->get($results_url)->result;
    die 'Unable to fetch: '.$res->code
        unless $res->is_success;
    my $tabs = {};
    $res->dom->find('ul.restabs li')->each(sub($li, $n) {
        $tabs->{lc $li->at('a')->text} = $n-1;
    });
    $tabs->{gc} = 0 if ($ttt && exists $tabs->{gc});

    my $tables = $res->dom->at('div.content')->find('table.results')->to_array;
    my $ret = {
        stage => [],
        gc => [],
    };

    if (exists $tabs->{stage}) {
        $ret->{stage} = _parse_result_rows($tables->[$tabs->{stage}])->to_array;
    }
    if (exists $tabs->{gc}) {
        $ret->{gc} = _parse_result_rows($tables->[$tabs->{gc}])->to_array;
    }
    return $ret;
}

sub _parse_result_rows($tbl) {
    my $idx = {};
    $tbl->at('thead')->find('th')->each(sub($hh, $n) {
        $idx->{lc $hh->text} = $n-1;
    });

    $tbl->at('tbody')->find('tr')->map(sub ($row) {
        my $cols = $row->find('td')->to_array;
        my $name = _transform_name($cols->[$idx->{rider}]->at('a')->text);
        if ($cols->[$idx->{rnk}]->text =~ /^(DN[FS]|OTL)$/) {
            return {
                rank => undef,
                name => $name,
                team => $cols->[$idx->{team}]->at('a')->text,
                uci_points => undef,
                time => undef,
            }
        }

        my $time = $cols->[$idx->{time}]->text;
        unless ($time) {  # only first row has only text
            $time = $cols->[$idx->{time}]->at('div')->text;
        }
        my $team = $cols->[$idx->{team}]->at('a');

        return {
            rank => $cols->[$idx->{rnk}]->text + 0,
            name => $name,
            team => $team ? $team->text : '-',
            uci_points => ($cols->[$idx->{uci}]->text||0) + 0,
            time => $time,
        }
    });
}

sub _filename($race_info) {
    return "data/race-".$race_info->{start_date}."-".slugify($race_info->{race}).".json";
}

sub read_race($self, $race_info) {
    no warnings 'experimental';
    my $race;
    try {
        $race = decode_json(Mojo::File->new(_filename($race_info))->slurp);
    }
    catch ($e) {}
    return $race;
}

sub write_race($self, $race_info) {
    my $fn = _filename($race_info);
    Mojo::File->new($fn)->spurt(
        encode_json($race_info)
    );
    return $fn;
}

1;
