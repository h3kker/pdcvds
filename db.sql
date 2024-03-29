PRAGMA encoding="UTF-8";
CREATE TABLE teams (
        uid int not null, 
    name text, 
    mine boolean default false,
    year integer not null,
    primary key (uid, year)
);
CREATE TABLE riders (
    pid int primary key not null, 
    name text not null, 
    dob text , 
    nationality text,
    spec_gc integer,
    spec_oneday integer,
    spec_tt integer,
    spec_climber integer,
    spec_sprint integer
);

CREATE TABLE rider_prices(
    pid integer not null,
    year integer not null,
    price integer not null,
    foreign key (pid) references riders(pid),
    primary key(pid, year)
    );
CREATE TABLE races (
    race integer primary key,
    name text,
    stage boolean,
    date text
);
CREATE TABLE stages(
    race integer not null,
    num integer,
    date text,
    foreign key (race)references races(race),
    primary key(race, num)
);
CREATE TABLE uci_teams(
    name text not null,
    short text primary key,
    cat text
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
    foreign key (short) references uci_teams(short),
    primary key(year, pid, short, year)
);
CREATE TABLE results(
    type text,
    pos integer,
    pid integer not null,
    points integer not null,
    race integer not null,
    stage integer,
    foreign key(pid) references riders(pid),
    foreign key(race) references races(race)
);
