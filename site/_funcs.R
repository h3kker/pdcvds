library(dplyr)
library(jsonlite)
library(lubridate)

load_team <- function(fn) {
    team <- fromJSON(fn)

    team$standings <- team$standings %>%
        mutate(date = ymd_hms(date), position = as.numeric(position))
    team$results <- team$results %>%
        mutate(date = ymd_hms(date))
    team
}

load_race <- function(fn) {
    ll <- fromJSON(fn)
    bind_cols(ll$riders,
        race = ll$race,
        start_date = ymd(ll$start_date),
        end_date = ymd(ll$end_date)
    )
}