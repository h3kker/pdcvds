
library(dplyr)
library(lubridate)
library(tidyr)
cur_year <- 2024

pdc_db <- DBI::dbConnect(RSQLite::SQLite(), "../pdcvds.db")
riders <- as_tibble(tbl(pdc_db, "riders")) %>%
  mutate(dob=ymd(dob), born=year(dob))
teams <- as_tibble(tbl(pdc_db, "teams")) %>% mutate(mine=mine==1)
team_riders <- as_tibble(tbl(pdc_db, "team_riders"))
races <- as_tibble(tbl(pdc_db, "races")) %>%
  mutate(start_date=ymd(start_date), end_date = ymd(end_date))
stages <- as_tibble(tbl(pdc_db, "stages")) %>%
  mutate(date = ymd(date))
race_results <- as_tibble(tbl(pdc_db, "race_results"))
riders_seen <- as_tibble(tbl(pdc_db, "riders_seen"))
riders_prices <- as_tibble(tbl(pdc_db, "rider_prices"))
# add result date from stage/race
race_results <- race_results %>%
  left_join(stages) %>%
  inner_join(races, by=join_by(event_id, year)) %>%
  mutate(date = if_else(is.na(date), start_date, date)) %>%
  select(type = type.x, pos, pid, points, event_id, stage_id, year, date)