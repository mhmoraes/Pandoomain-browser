#!/usr/bin/env Rscript

# Globals ----

suppressPackageStartupMessages({
  library(tidyverse)
})

argv <- commandArgs(trailingOnly = TRUE)

NEIGHBORS <- argv[[1]]
ARCHS <- argv[[2]]

# ARCHS <- "tests/results/archs.tsv"
# NEIGHBORS <- "tests/results/neighbors.tsv"

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

get_relative_arch <- function(strand, neoff, arch) {
  if_else(strand[neoff == 0] == strand, arch, invert_architectures(arch))
}

join_archs <- function(arch) {
  str_flatten(arch[!is.na(arch)], collapse = "|")
}


# Main ----

archs <- read_tsv(ARCHS)
neighbors <- read_tsv(NEIGHBORS)

neighbors <- left_join(neighbors, archs, join_by(pid))



neighbors <- neighbors |>
  group_by(genome, neid) |>
  mutate(
    relarchMEM = get_relative_arch(strand, neoff, archMEM),
    relarchPF = get_relative_arch(strand, neoff, archPF),
    relarchIPR = get_relative_arch(strand, neoff, archIPR)
  )



out <- neighbors |>
  summarize(
    neID = paste0(unique(genome), "_", "n", unique(neid)),
    hit = pid[neoff == 0],
    gene = gene[neoff == 0],
    product = product[neoff == 0],
    queries = unique(queries),
    start_ext = first(start),
    end_ext = last(end),
    length_ext = abs(end_ext - start_ext) + 1,
    starto_ext = first(order),
    endo_ext = last(order),
    lengtho_ext = abs(endo_ext - starto_ext) + 1,
    contig = unique(contig),
    locus_tag = locus_tag[neoff == 0],
    strands = str_flatten(strand, collapse = ""),
    archMEM = archMEM[neoff == 0],
    archPF = archPF[neoff == 0],
    archIPR = archIPR[neoff == 0],
    archMEM_ext = join_archs(relarchMEM),
    archPF_ext = join_archs(relarchPF),
    archIPR_ext = join_archs(relarchIPR)
  )



out |>
  select(
    neID, hit, queries, gene,
    product, genome, contig, locus_tag,
    start_ext, end_ext, length_ext,
    starto_ext, endo_ext, lengtho_ext, strands,
    archMEM, archPF, archIPR,
    archMEM_ext, archPF_ext, archIPR_ext
  ) |>
  format_tsv() |>
  writeLines(stdout(), sep = "")
