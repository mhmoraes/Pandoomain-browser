#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(tidyverse)
})

argv <- commandArgs(trailingOnly = TRUE)

TAXA <- argv[[1]]
HITS <- argv[[2]]
ARCHS <- argv[[3]]

# TAXA <- "tests/results/genomes_ranks.tsv"
# HITS <- "tests/results/hmmer.tsv"
# ARCHS <- "tests/results/archs.tsv"


TAXA_SEL <- c(
  "genome", "tax_id",
  "superkingdom",
  "phylum", "class", "order",
  "family", "genus", "species"
)


ranks <- read_tsv(TAXA, show_col_types = FALSE) |>
  select(all_of(TAXA_SEL))
hits <- read_tsv(HITS, show_col_types = FALSE) |>
  select(genome, pid)
archs <- read_tsv(ARCHS, show_col_types = FALSE) |>
  select(pid, archPF)


archsNF <- archs |>
  filter(!is.na(archPF)) |>
  group_by(pid) |>
  reframe(pfam = str_split_1(archPF, pattern = "\\|"))


genome_pfam <- left_join(hits, archsNF, join_by(pid)) |>
  group_by(genome) |>
  summarize(pfams = str_flatten(sort(unique(pfam)), collapse = "|"))

left_join(genome_pfam, ranks) |>
  format_tsv() |>
  writeLines(stdout(), sep = "")
