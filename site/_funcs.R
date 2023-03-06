library(dplyr)
library(jsonlite)
library(lubridate)

load_team <- function(fn) {
    team <- fromJSON(fn)

    team$riders <- team$riders %>%
        mutate(price = as.numeric(price))
    team$standings <- team$standings %>%
        mutate(date = ymd_hms(date), position = as.numeric(position))
    team$scores <- team$scores %>%
        mutate(date = ymd_hms(date), score = as.numeric(score))
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