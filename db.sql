PRAGMA encoding="UTF-8";
CREATE TABLE teams (
        uid int not null, 
        name text, 
        mine boolean default false,
        year integer not null,
    primary key (uid, year)
);
CREATE TABLE riders (
    pid int not null, 
    name text not null, 
    dob text, 
    born integer,
    country text,
    country_long text,
    spec_gc integer,
    spec_oneday integer,
    spec_tt integer,
    spec_climber integer,
    spec_sprint integer,
    primary key(pid)
);

CREATE TABLE riders_seen(
pid int not null,
year int not null,
primary key(pid, year),
foreign key(pid) references riders(pid)
);

CREATE TABLE rider_prices(
    pid integer not null,
    year integer not null,
    price integer not null,
    foreign key (pid) references riders(pid),
    primary key(pid, year)
    );
CREATE TABLE races (
    event_id integer ,
    name text,
    type text,
    country text,
    category text,
    start_date text,
    end_date text,
    primary key (event_id)
);
CREATE TABLE stages(
    event_id integer not null,
    stage_id integer,
    num text,
    date text,
    foreign key (event_id) references races(event_id),
    primary key(stage_id)
);
CREATE TABLE uci_teams(
    name text not null,
    short text,
    cat text,
    year integer,
    primary key(short, year)
);
CREATE TABLE team_riders(
    year integer,
    pid integer not null, 
    uid integer not null,
    foreign key(pid)references riders(pid), 
    foreign key (uid) references teams(uid),
    primary key(year, pid, uid)

);
CREATE TABLE uci_team_riders(
    year integer not null,
    pid integer not null, 
    short text not null, 
    foreign key(pid) references riders(pid) 
    foreign key (short, year) references uci_teams(short, year),
    primary key(year, pid, short)
);
CREATE TABLE race_results(
    type text,
    pos integer,
    pid integer not null,
    points integer not null,
    event_id integer not null,
    stage_id integer,
    foreign key(pid) references riders(pid),
    foreign key(event_id) references races(event_id),
    foreign key(stage_id) references stages(stage_id)
);
