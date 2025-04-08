#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(tidyverse)
  library(rlang)
  library(glue)
})

argv <- commandArgs(trailingOnly = TRUE)

# ARCHS <- argv[[1]]
# NEIGHBORS <- argv[[2]]

HMMER <- "tests/results/hmmer.tsv"
NEIGHBORS <- "tests/results/neighbors.tsv" 

# Main ----

hmmer <- read_tsv(HMMER)
neighbors <- read_tsv(NEIGHBORS)

ne0 <- neighbors |>
  filter(neoff == 0)

nepids <- ne0 |> pull(pid) |> unique() |> length()
hmpids <- hmmer |> pull(pid) |> unique() |> length()


if (nepids != hmpids) {
  warn(glue("Weird Stuff: hits on \n\t+ {NEIGHBORS}\n\t+ {HMMER}\nare not equal."))
}

dim(ne0)
dim(hmmer)
