#!/usr/bin/env Rscript

# Globals ----

suppressPackageStartupMessages({
  library(tidyverse)
})

argv <- commandArgs(trailingOnly = TRUE)

# ARCHS <- argv[[1]]
# NEIGHBORS <- argv[[2]]

ARCHS <- "tests/results/archs.tsv"
NEIGHBORS <- "tests/results/neighbors.tsv"

# Helpers ----


invert_architectures <- function(archs_char) {
  reverse_single_arch <- function(x) {
    if (is.na(x)) {
      return(NA)
    } else {
      return(
        x |>
          str_split_1(pattern = "\\|") |>
          rev() |>
          str_flatten(collapse = "|")
      )
    }
  }

  map_chr(archs_char, reverse_single_arch)
}

# Main ----

archs <- read_tsv(ARCHS)
neighbors <- read_tsv(NEIGHBORS)

neighbors <- left_join(neighbors, archs, join_by(pid))


get_relative_arch <- function(strand, neoff, arch) {
  if_else(strand[neoff == 0] == strand, arch, invert_architectures(arch))
}


neighbors <- neighbors |>
  group_by(genome, neid) |>
  mutate(
    rel_archMEM = get_relative_arch(strand, neoff, archMEM),
    rel_archPF = get_relative_arch(strand, neoff, archMEM)
  )
