#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(tidyverse)
})


argv <- commandArgs(trailingOnly = TRUE)

ISCAN <- argv[[1]]
# ISCAN <- "tests/results/iscan.tsv"


# Main ----


iscan <- read_tsv(ISCAN, show_col_types = FALSE)

iscan_summary <- iscan |>
  select(pid, memberDB, interpro, start, end, length, memberDB_txt) |>
  arrange(pid, start)

stopifnot("Separator is used by a memberDB ID." = all(!str_detect(iscan_summary$memberDB, "\\|")))
stopifnot("Unexpeted NA on memberDB field." = all(!is.na(iscan_summary$memberDB)))

is_unique <- function(x) {
  all(sort(unique(x)) == sort(x))
}

archsMEM <- iscan_summary |>
  group_by(pid) |>
  summarize(
    archMEM = str_flatten(memberDB, collapse = "|")
  )

# archs IPR ----


iscanIPR <- iscan_summary |>
  filter(!is.na(interpro))

delta_lag <- function(x) {
  abs(lag(x) - x)
}

deltaENDs <- iscanIPR |>
  group_by(pid, interpro) |>
  reframe(
    start = start,
    end = end,
    deltaS = delta_lag(start),
    deltaE = delta_lag(end)
  )

includeIPR <- function(dS, dE) {
  CUTOFF <- 36
  firstIPR <- is.na(dS) & is.na(dE)
  restIPR <- (dS > CUTOFF) | (dE > CUTOFF)
  restIPR[is.na(restIPR)] <- TRUE
  firstIPR & restIPR
}


archsIPR <- deltaENDs |>
  mutate(valid = includeIPR(deltaS, deltaE)) |>
  filter(valid) |>
  group_by(pid) |>
  arrange(start) |>
  summarize(
    archIPR = str_flatten(interpro, collapse = "|")
  )

# archs PFAM ----


archMEM_to_archPF <- function(arch_mem) {
  f <- function(x) {
    all_arch <- str_split_1(x, pattern = "\\|")
    PF_valid <- str_detect(all_arch, "^PF[:digit:]{5}")
    str_flatten(all_arch[PF_valid], collapse = "|")
  }
  map_chr(arch_mem, f)
}

archsPF <- archsMEM |>
  mutate(archsPF = archMEM_to_archPF(archMEM))

# archs all ----

archs <- left_join(archsPF, archsIPR, join_by(pid))

archs |>
  format_tsv() |>
  writeLines(stdout(), sep = "")
