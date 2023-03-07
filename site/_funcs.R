library(dplyr)
library(jsonlite)
library(lubridate)
library(tidyr)

load_team <- function(fn) {
    team <- fromJSON(fn)

    team$standings <- team$standings %>%
        mutate(date = ymd_hms(date), position = as.numeric(position))
    team$results <- team$results %>%
        mutate(date = ymd_hms(date))
    team$riders <- team$riders %>% full_join(
        team$specialties %>%
            pivot_longer(!pid, names_to = "spec", values_to = "pcs_score") %>%
            group_by(pid) %>%
            mutate(total = sum(pcs_score)) %>%
            slice_max(n = 1, order_by = pcs_score) %>%
            mutate(spec_rate = round(pcs_score/total*100)) %>%
            select(pid, spec, spec_rate),
        by = c("pid")
    )
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