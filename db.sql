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
    born integer,
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
    event integer primary key,
    name text,
    type text,
    country text,
    start_date text,
    end_date text
);
CREATE TABLE stages(
    race integer not null,
    stage int primarty key,
    num integer,
    date text,
    foreign key (race)references races(event)
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
    primary key(year, pid, short, year)
);
CREATE TABLE results(
    type text,
    pos integer,
    pid integer not null,
    points integer not null,
    event integer not null,
    stage integer,
    foreign key(pid) references riders(pid),
    foreign key(event) references races(event),
    foreign key(stage) references stages(stage)
);
