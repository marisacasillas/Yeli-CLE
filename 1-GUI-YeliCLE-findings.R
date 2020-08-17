# rm(list = ls())
library(tidyverse)
library(gtools)

basic.theme <- theme(
	panel.background = element_rect(
		fill = "transparent",colour = NA),
	panel.grid.major = element_line(colour = "gray50"),
#	panel.grid.minor = element_blank(),
	plot.background = element_rect(
		fill = "transparent",colour = NA),
	legend.background = element_rect(
		fill="transparent"),
	legend.key = element_rect(colour = NA, fill = NA),
	legend.key.height = unit(2, "lines"),
	panel.spacing = unit(2, "lines"))

retrieve.summary <- function(sample, version, measures) {
  ################################################################################
  # Set up
  ################################################################################
  
  # sample <- "Random"
  # version <- "Casillas, Brown, & Levinson (accepted August 2020)"
  # measures <- "TCDS"
  # model <- "Yes" (not currently an option)

  all.sum.stats <- read_csv("shiny_input/quantity-scores_rand-and-tt.csv")
  measure <- case_when(
    grepl("TCDS", measures) ~ "tds_mph",
    grepl("ODS", measures) ~ "ods_mph",
    grepl("XDS", measures) ~ "xds_mph",
  )
  all.sum.stats$curr.measure <- pull(
    all.sum.stats[,which(names(all.sum.stats) == measure)])

  if (sample == "High turn-taking") {
    sample <- "Turn taking"
  }
    
  sum.stat.tbl.a <- filter(all.sum.stats, Sample == sample) %>%
    rowwise() %>%
    mutate(age_months = str_pad(
      formatC(age_mo_round, digits = 2, format = "f"), 5, "left", "0")) %>%
    select(-age_mo_round) %>%
    group_by(age_months) %>%
    summarise(mean = mean(curr.measure),
              median = median(curr.measure),
              min = min(curr.measure),
              max = max(curr.measure),
              n_clips = n())
  sum.stat.tbl.b <- filter(all.sum.stats, Sample == sample) %>%
    summarise(age_months = "All",
              mean = mean(curr.measure),
              median = median(curr.measure),
              min = min(curr.measure),
              max = max(curr.measure),
              n_clips = n())
  sum.stat.tbl <- bind_rows(sum.stat.tbl.a, sum.stat.tbl.b)
  
  sum.stat.fig <- ggplot(data=all.sum.stats,
                         aes(x = age_mo_round, y = curr.measure)) +
    geom_boxplot(aes(group = age_mo_round), fill = "forestgreen",
                 alpha = 0.4, outlier.shape = NA) +
    geom_jitter(aes(group = age_mo_round), color = "forestgreen",
                alpha = 0.4) +
    xlab("Age (months)") +
    ylab(measures) +
    basic.theme
  
  all.models <- read_csv("shiny_input/all_model_tables.csv")
  
  if (grepl("TCDS", measures)) {
    if (sample == "Random") {
      model.output.tbl <- filter(all.models, model == "TCDS_random_z-inb")
      model.res.fig <- "TCDS_random_z-inb_res_plot.png"
    } else if (sample == "Turn taking") {
      model.output.tbl <- filter(all.models, model == "TCDS_turntaking_nb")
      model.res.fig <- "TCDS_turntaking_nb_res_plot.png"
    } else {
      model.output.tbl <- tibble()
      model.res.fig <- NULL
    }
  } else if (grepl("ODS", measures)) {
    if (sample == "Random") {
      model.output.tbl <- filter(all.models, model == "ODS_random_nb")
      model.res.fig <- "ODS_random_nb_res_plot.png"
    } else if (sample == "Turn taking") {
      model.output.tbl <- filter(all.models, model == "ODS_turntaking_nb")
      model.res.fig <- "ODS_turntaking_nb_res_plot.png"
    } else {
      model.output.tbl <- tibble()
      model.res.fig <- NULL
    }
  } else if (grepl("XDS", measures)) {
    model.output.tbl <- tibble()
    model.res.fig <- NULL
  }

  return(list(
    sum.stat.tbl = sum.stat.tbl,
    sum.stat.fig = sum.stat.fig,
    model.output.tbl = model.output.tbl,
    model.res.fig = model.res.fig
  ))
}

