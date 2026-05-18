#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(tidyverse)
})


argv <- commandArgs(trailingOnly = TRUE)

ISCAN <- argv[[1]]
OUT <- argv[[2]]
OUT_PIDFOCUS <- argv[[3]]
OUT_CODE <- argv[[4]]

OFFSET <- 33
PF_INT_LEN <- 5
PF_LEAD_CHAR <- "PF"

one_lettercode <- function(doms) {
  doms <- unique(doms)
  pfam_chars <- str_extract(doms, "\\d+")
  stopifnot("Bad PFAM ID." = all(str_length(pfam_chars) == PF_INT_LEN))
  pfam_ints <- as.integer(pfam_chars)
  stopifnot("Some extracted PFAM IDs are NA." = all(!is.na(pfam_ints)))
  stopifnot("Unicode points out of range." = all((pfam_ints + OFFSET) <= 0x10FFFF))
  pfam_codes <- strsplit(intToUtf8(pfam_ints + OFFSET), "")[[1]]
  stopifnot("Conversion to utf-8 failed." = length(pfam_codes) == length(doms))
  OUT <- as.list(pfam_codes)
  names(OUT) <- doms
  OUT
}

code_to_pfam <- function(codes) {
  TOTAL_LEN <- PF_INT_LEN + str_length(PF_LEAD_CHAR)
  pfam_ints <- utf8ToInt(codes) - OFFSET
  pfam_chars <- as.character(pfam_ints)
  appends <- map_chr(
    PF_INT_LEN - str_length(pfam_chars),
    \(x) ifelse(x > 0, str_flatten(rep("0", x)), "")
  )
  OUT <- str_c(PF_LEAD_CHAR, appends, pfam_chars)
  stopifnot("Bad PFAM ID" = all(str_length(OUT) == TOTAL_LEN))
  OUT
}

replace_to_oneletter <- function(archs, code) {
  keys <- names(code)
  for (key in keys) {
    archs <- str_replace_all(archs, key, code[[key]])
  }
  str_replace_all(archs, ",", "")
}

get_arch_len <- function(arch) {
  str_split(arch, ",") |>
    map_int(length)
}


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
  mutate(archPF = archMEM_to_archPF(archMEM))

# archs all ----

archs <- left_join(archsPF, archsIPR, join_by(pid))

write_tsv(archs, OUT)

# Legacy pidrow and code outputs

archs_legacy <- iscan |>
  filter(analysis == "Pfam") |>
  group_by(pid) |>
  reframe(
    domain = memberDB, start = start, end = end,
    length = length, domain_txt = memberDB_txt
  ) |>
  arrange(pid, start, end) |>
  mutate(
    start = as.integer(start),
    end = as.integer(end),
    length = as.integer(length)
  )

archs_legacy <- archs_legacy |>
  group_by(pid) |>
  reframe(order = 1:length(start), across(everything())) |>
  relocate(order, .after = domain)

pid_focus <- archs_legacy |>
  group_by(pid) |>
  summarize(
    pid = unique(pid),
    arch = str_flatten(domain, collapse = ",")
  )

ONE_LETTER <- one_lettercode(archs_legacy$domain)

pid_focus <- pid_focus |>
  left_join(
    distinct(archs_legacy, pid, length),
    join_by(pid)
  ) |>
  mutate(ndoms = get_arch_len(arch)) |>
  relocate(ndoms, .after = arch)

pid_focus <- pid_focus |>
  mutate(arch_code = replace_to_oneletter(arch, ONE_LETTER))

one_letter_chr <- ONE_LETTER |>
  unlist()

one_letter_tib <- tibble(
  domain = names(one_letter_chr),
  letter = one_letter_chr
)

write_tsv(pid_focus, OUT_PIDFOCUS)
write_tsv(one_letter_tib, OUT_CODE)
