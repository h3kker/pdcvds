package ProcyclingStats;

use v5.36;

use Mojo::UserAgent;
use Mojo::JSON qw(encode_json);
use Mojo::File;
use Mojo::Util qw(slugify);
use Mojo::URL;
use DateTime;
use utf8;

use Moose;

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
    
    my $infos = $ov_res->dom->at('ul.infolist')->find('li')->to_array;
    return {
        start_date => $infos->[0]->find('div')->last->text,
        end_date => $infos->[1]->find('div')->last->text,
        race => $ov_res->dom->at('div.main h1')->text,
        link => $race_url,
    }
}

sub start_list($self, $race_url) {
    my $start_url = $race_url;
    $start_url =~ s,/overview$,,;
    $start_url .= '/startlist';

    my $res = $self->ua->get($start_url.'/riders-ranked')->result;
    die 'Unable to fetch: '.$res->code 
        unless $res->is_success;
    
    my $list = $res->dom->at('div.content table.basic tbody')->find('tr');
    return $list->map(sub($row) {
        my $cols = $row->find('td')->to_array;
        my $rank = $cols->[0]->text;
        my $name = $cols->[1]->at('a')->all_text;
        # ranked table uses css to uppercase lastname, elsewhere
        # it is hard uppercase.
        $name =~ /^([\p{Word}\-' ]+) (.+)$/;
        die "$name does not match"
            unless $1 && $2;
        return {
            # force name to title case
            name => sprintf("%s %s" => $2, join('', map { ucfirst(lc $_) } split "([ '-])", $1)),
            team => $cols->[2]->at('a')->text,
            rank => $rank + 0,
        };
    });
}

sub write_race($self, $race_info) {
    my $fn = "data/startlist-".$race_info->{start_date}."-".slugify($race_info->{race}).".json";
    Mojo::File->new($fn)->spurt(
        encode_json($race_info)
    );
    return $fn;
}

1;