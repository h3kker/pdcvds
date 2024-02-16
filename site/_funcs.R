library(dplyr)
library(jsonlite)
library(lubridate)
library(tidyr)
library(stringr)

race_name_fixups <- c(
    "GP de Denain Porte du Hainaut" = "Grand Prix de Denain - Porte du Hainaut",
    "Kuurne - Brussel - Kuurne" = "Kuurne - Bruxelles - Kuurne",
    "Omloop Het Nieuwsblad" = "Omloop Het Nieuwsblad ME",
    "Grand Prix Criquelion" = "Grand Prix Criquielion"
)

load_team <- function(fn) {
    team <- fromJSON(fn)

    if (length(team$standings) > 0) {
        team$standings <- team$standings %>%
            mutate(date = ymd_hms(date), position = as.numeric(position))

    }
    if (length(team$results) > 0) {
        team$results <- team$results %>%
            mutate(
                date = ymd_hms(date),
                pcs_race = coalesce(race_name_fixups[race], race),
                stage_name = stage,
                stage=str_extract(stage_name, '^\\d+')
            )
    }
    team$riders <- team$riders %>% full_join(
        team$specialties %>%
            pivot_longer(!pid, names_to = "spec", values_to = "pcs_score") %>%
            group_by(pid) %>%
            mutate(total = sum(pcs_score)) %>%
            slice_max(n = 1, order_by = pcs_score, with_ties = FALSE) %>%
            mutate(spec_rate = round(pcs_score/total*100)) %>%
                select(pid, spec, spec_rate),
        by = c("pid")
        )
    team
}

load_race <- function(fn) {
    ll <- fromJSON(fn, simplifyVector = FALSE)
    common_info <- bind_cols(
            race = ll$race,
            start_date = ymd(ll$start_date),
            end_date = ymd(ll$end_date),
            link = ll$link
    )

    results <- list()
    if ("stages" %in% names(ll$results)) {
        results <- bind_rows(
            bind_cols(common_info, bind_rows(ll$results$final), type = "gc"),
            bind_rows(lapply(ll$results$stages, function(ss) {
                bind_cols(
                    common_info,
                    bind_rows(ss$result),
                    stage_date = ymd(ss$stage_date),
                    stage = ss$stage,
                    type = "stage"
                )
            }))
        )
    } else {
        results <- bind_cols(
            common_info,
            bind_rows(ll$results$final),
            type = "oneday"
        )
    }

    list(
        start_list = bind_cols(
            bind_rows(ll$riders),
            common_info
        ),
        results = results
    )
}

load_races <- function() {
    all_races <- lapply(Sys.glob("../data/race-*.json"), load_race)
    list(
        start_lists = bind_rows(lapply(all_races, function(rr) rr$start_list)),
        results = bind_rows(lapply(all_races, function(rr) rr$results))
    )
}
