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
    $rows->each(sub($r, $n) {
        my $cols = $r->find('td')->to_array;
        my @date = split ' - ', $cols->[0]->text;
        my $start = _get_date($date[0]);
        return
            if ($start > $next_week);
        
        my $race_name = $cols->[1]->at('a')->text;
        say "fetch ".$race_name;
        my $start_list = $cols->[4]->at('a')->attr('href');
        $self->startlist($self->base_url.'/'.$start_list);
    });
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

sub startlist($self, $start_url) {
    my @subs = ('result/overview', 'gc/overview');
    my $ov_res;
    for my $sub (@subs) {
        my $overview_url = $start_url;
        $overview_url =~ s,(result/)?startlist$,$sub,;
        $ov_res = $self->ua->get($overview_url)->result;
        die 'Unable to fetch: '.$ov_res->code
            unless $ov_res->is_success;
        
        unless ($ov_res->dom->at('div.main h1')->text eq 'Page not found') {
            last;
        }
    }

    my $infos = $ov_res->dom->at('ul.infolist')->find('li')->to_array;
    my $start_date = $infos->[0]->find('div')->last->text;
    my $end_date = $infos->[1]->find('div')->last->text;

    my $res = $self->ua->get($start_url)->result;
    die 'Unable to fetch: '.$res->code
    unless $res->is_success;

    my $race = $res->dom->at('div.main h1')->text;

    my $list = $res->dom->at('ul.startlist_v3')->find('li.team');

    my $riders = $list->map(sub($t) {
        my $team = $t->at('b a')->text;
        return $t->find('ul li')->map(sub($r) {
            my $number = $r->text;
            $number =~ tr/ //d;
            my $name = $r->at('a span')->text;
            $name =~ /^([\p{Upper}\-'ß ]+) (.+)$/;
            die "$name does not match"
            unless $1 && $2;
            return {
                name => sprintf("%s %s" => $2, join('', map { ucfirst(lc $_) } split "([ '-])", $1)),
                team => $team,
                number => $number,
            }
        });
    })->flatten;

    Mojo::File->new("data/startlist-".$start_date."-".slugify($race).".json")->spurt(
        encode_json({
            race => $race,
            start_date => $start_date,
            end_date => $end_date,
            riders => $riders->TO_JSON
        })
    );
}

1;