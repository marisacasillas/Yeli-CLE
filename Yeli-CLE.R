library(papaja)
library(ggplot2)
library(tidyverse)
library(viridis)
library(grid)
library(gridExtra)
library(ggpirate)
library(lme4)
library(glmmTMB)
library(DHARMa)
library(bbmle)
source("0-Helper.R")

options(scipen=999)
data.path <- "transcripts/anon/" # text files exported from ELAN
plot.path <- "plots/" # output plots
seg.index.file <- "Segment-order-inventory.csv"
ptcp.info.file <- "recording-info.csv"
samplelabels <- c("High activity  ", "Random  ")
col.sample.bu <- list(
  scale_fill_manual(labels=samplelabels, values=viridis(2)),
  scale_color_manual(labels=samplelabels, values=viridis(2)))
col.sample.bu3 <- list(
  scale_fill_manual(labels=samplelabels, values=viridis(3)),
  scale_color_manual(labels=samplelabels, values=viridis(3)))
allowed.overlap <- 1000 #ms
allowed.gap <- 2000 #ms

# Read in supplementary data
ptcp.info <- read_csv(ptcp.info.file, col_types = cols()) %>%
  dplyr::select(-row)
seg.info <- read_csv(seg.index.file)

# Read in annotation files
files <- list.files(path=data.path,pattern="*.txt")
all.data <- data.frame()
for (i in 1:length(files)) {
#  print(files[i])
  newfile <- read_csv(paste0(data.path, files[i]), col_types = cols(val = col_character()))
  other_child_id <- unlist(strsplit(files[i], '[_]'))[1]
  newfile$Media <- unlist(strsplit(files[i], '\\.'))[1]
  newfile$aclew_child_id <- ptcp.info$aclew_child_id[which(ptcp.info$other_child_id == other_child_id)]
  all.data <- rbind(all.data, newfile)
}
all.data$row <- c(1:nrow(all.data))


# Extract and convert start time of each sample
seg.info$start.hhmmss <- regmatches(seg.info$Media,
                                    regexpr("[[:digit:]]{6}", seg.info$Media))
seg.info$start.sec <- as.numeric(substr(seg.info$start.hhmmss,1,2))*3600 +
  as.numeric(substr(seg.info$start.hhmmss,3,4))*60 +
  as.numeric(substr(seg.info$start.hhmmss,5,6))
seg.info$start.hr <- round(seg.info$start.sec/3600, 3)

seg.info$clipoffset.hhmmss <- regmatches(seg.info$Media,
                                    regexpr("(?<=[[:digit:]]{6}_)[[:digit:]]{6}",
                                            seg.info$Media, perl = TRUE))
seg.info$clipoffset.sec <- as.numeric(substr(seg.info$clipoffset.hhmmss,1,2))*3600 +
  as.numeric(substr(seg.info$clipoffset.hhmmss,3,4))*60 +
  as.numeric(substr(seg.info$clipoffset.hhmmss,5,6))
seg.info$clipoffset.hr <- round(seg.info$clipoffset.sec/3600, 3)

# Add mean and sd values for participant-level predictors to ptcp.info
ptcp.info <- ptcp.info %>%
  mutate(
    tchiyr.m = mean(age_mo_round),
    motyr.m = mean(mother_age),
    nsb.m = mean(number_older_sibs),
    hsz.m = mean(household_size),
    tchiyr.sd = sd(age_mo_round),
    motyr.sd = sd(mother_age),
    nsb.sd = sd(number_older_sibs),
    hsz.sd = sd(household_size)
    )

# Merge in participant and segment info to the main data table
#codes <- all.data %>% filter(tier == "code")

all.data <- all.data %>%
  filter(speaker != "") %>%
  left_join(ptcp.info, by = "aclew_child_id") %>%
  mutate(segment = "", sample = "",
         sample_type = "", segment_dur = 0)

#for (i in 1:nrow(codes)) {
#  rec <- codes$aclew_child_id[i]
#  seg <- as.character(codes$val[i])
#  seg.on <- codes$start[i]
#  seg.off <- codes$stop[i]
#  seg.idx <- which(all.data$aclew_child_id == rec &
#                     all.data$start < seg.off &
#                     all.data$stop > seg.on)
#  all.data$segment[seg.idx] <- seg
#}

# Label samples
all.data$sample  <- "random"

#all.data$sample[which(
#  grepl('^random', all.data$segment))] <- "random"
#all.data$sample[which(
#  grepl('tt', all.data$segment))] <- "turn-taking"
#all.data$sample[which(
#  grepl('va', all.data$segment))] <- "high-activity"

# Label sample types and durations
all.data$sample_type  <- "random"
all.data$segment_dur  <- 2.5

#random.samples <- which(grepl('^random', all.data$segment))
#all.data$sample_type[random.samples] <- "random"
#all.data$segment_dur[random.samples] <- 5

#ext.samples <- which(grepl('^extension', all.data$segment))
#all.data$sample_type[ext.samples] <- "extension"
#all.data$segment_dur[ext.samples] <- 5

#tt.samples <- which(grepl('^tt', all.data$segment))
#all.data$sample_type[tt.samples] <- "turn-taking"
#all.data$segment_dur[tt.samples] <- 1

#va.samples <- which(grepl('^va', all.data$segment))
#all.data$sample_type[va.samples] <- "turn-taking"
#all.data$segment_dur[va.samples] <- 1

# Add in segment start time
all.data <- all.data %>%
  left_join(dplyr::select(seg.info, c("aclew_id", "CodeName", "Media", "start.hhmmss",
                                      "start.sec", "start.hr")),
            by = c("aclew_child_id" = "aclew_id", "Media" = "Media"))
all.data$segment <- all.data$CodeName

ptcp.info <- mutate(ptcp.info,
                    rec.start.hr = lubridate::hour(start_of_recording) +
                      lubridate::minute(start_of_recording)/60 +
                      lubridate::second(start_of_recording)/3600,
                    rec.stop.hr = rec.start.hr + length_of_recording/3600) %>%
  arrange(age_mo_round) %>%
  mutate(order = seq(1:10))

# RANDOM
# Get min/hr speech measures
n.unique.rand.segs <- length(unique(all.data$segment[grepl("random", all.data$segment)]))
n.unique.recs <- length(unique(all.data$aclew_child_id))
all.rand.segments <- tibble(
  aclew_child_id = rep(unique(all.data$aclew_child_id),
                n.unique.rand.segs),
  segment = rep(unique(all.data$segment[grepl("random", all.data$segment)]),
                n.unique.recs))

# get rid of annotations after 2m30s
all.data <- filter(all.data, start < (60000*2.5))

# sanity check that there are the right number of xds annots
test <- all.data %>%
  filter(speaker != "CHI") %>%
  mutate(tiertype = ifelse(tier == speaker, "speaker", "xds")) %>%
  group_by(Media, tiertype) %>%
  summarise(nrows = n())


used.clips <- seg.info %>%
#  filter(Include == 1) %>%
  left_join(ptcp.info, by = c("aclew_id" = "aclew_child_id")) %>%
  mutate(clip.dur = ifelse(grepl(('random'), CodeName), 5,
                           ifelse(grepl('extension', CodeName), 6, 1)),
         sample.type = ifelse(grepl(('random'), CodeName), "Random",
                           ifelse(grepl('tt', CodeName), "Turn taking", "High activity")))
#used.clips$sample.type = factor(used.clips$sample.type, levels = c("Random", "Turn taking", "High activity"))

clip.distribution.1 <- ggplot() +
  geom_segment(data = ptcp.info,
               aes(x = rec.start.hr, y = order, xend = rec.stop.hr, yend = order), color = "white") +
  theme_apa() +
  scale_x_continuous(breaks = 7:21) +
  scale_y_continuous(breaks = 1:10, labels = ptcp.info$age_mo_round) +
  ylab("Child age (mo)") + xlab("Time of day (hr)") + labs(color = "Sample type") +
  basic.theme + theme(
		panel.grid.major = element_blank(),
		panel.grid.minor = element_blank(),
		axis.text.x = element_text(color="white"),
	  axis.title.x = element_text(color="white"),
	  axis.text.y = element_text(color="white"),
	  axis.title.y = element_text(color="white"),
	  strip.text = element_text(color="white"),
		axis.ticks = element_line(color = "white"),
		legend.position = "none")

clip.distribution.2 <- ggplot() +
  geom_segment(data = ptcp.info,
               aes(x = rec.start.hr, y = order, xend = rec.stop.hr, yend = order), color = "white") +
  geom_segment(data = subset(used.clips, sample.type == "Random"),
               aes(x = start.hr, y = order, xend = start.hr + clip.dur/60, yend = order,
                   color = sample.type), size = 10) +
  theme_apa() +
  scale_x_continuous(breaks = 7:21) +
  scale_y_continuous(breaks = 1:10, labels = ptcp.info$age_mo_round) +
  ylab("Child age (mo)") + xlab("Time of day (hr)") + labs(color = "Sample type") +
  scale_color_manual(values = c("white")) +
  basic.theme + theme(
		panel.grid.major = element_blank(),
		panel.grid.minor = element_blank(),
		axis.text.x = element_text(color="white"),
	  axis.title.x = element_text(color="white"),
	  axis.text.y = element_text(color="white"),
	  axis.title.y = element_text(color="white"),
	  strip.text = element_text(color="white"),
		axis.ticks = element_line(color = "white"),
		legend.position = "none")

png(paste("diff-figs/","clip.distribution.1.png", sep=""),
    width=1200, height=600,units="px", bg = "transparent")
print(clip.distribution.1)
dev.off()
png(paste("diff-figs/","clip.distribution.2.png", sep=""),
    width=1200, height=600,units="px", bg = "transparent")
print(clip.distribution.2)
dev.off()



# XDS
xds.per.seg.rand <- all.data %>%
  filter(sample == "random" & speaker != "CHI" &
           grepl("xds@", tier)) %>%
  group_by(aclew_child_id, segment, segment_dur) %>%
  summarise(xds_min = round(sum(dur)/60000,3)) %>%
  full_join(all.rand.segments, by = c("aclew_child_id", "segment")) %>%
  replace_na(list(segment_dur = 2.5, xds_min = 0)) %>%
  mutate(xds_mph = (xds_min/segment_dur)*60) %>%
  arrange(aclew_child_id, segment)
# ODS
ods.per.seg.rand <- all.data %>%
  filter(sample == "random" & speaker != "CHI" &
           grepl("xds@", tier) & val != "T") %>%
  group_by(aclew_child_id, segment, segment_dur) %>%
  summarise(ods_min = round(sum(dur)/60000,3)) %>%
  full_join(all.rand.segments, by = c("aclew_child_id", "segment")) %>%
  replace_na(list(segment_dur = 2.5, ods_min = 0)) %>%
  mutate(ods_mph = (ods_min/segment_dur)*60) %>%
  arrange(aclew_child_id, segment)
# TDS
tds.per.seg.rand <- all.data %>%
  filter(sample == "random" & speaker != "CHI" &
           grepl("xds@", tier) & val == "T") %>%
  group_by(aclew_child_id, segment, segment_dur) %>%
  summarise(tds_min = round(sum(dur)/60000,3)) %>%
  full_join(all.rand.segments, by = c("aclew_child_id", "segment")) %>%
  replace_na(list(segment_dur = 2.5, tds_min = 0)) %>%
  mutate(tds_mph = (tds_min/segment_dur)*60) %>%
  arrange(aclew_child_id, segment)
# All CDS
cds.per.seg.rand <- all.data %>%
  filter(sample == "random" & speaker != "CHI" &
           grepl("xds@", tier) & (val == "T" | val == "C")) %>%
  group_by(aclew_child_id, segment, segment_dur) %>%
  summarise(cds_min = round(sum(dur)/60000,3)) %>%
  full_join(all.rand.segments, by = c("aclew_child_id", "segment")) %>%
  replace_na(list(segment_dur = 2.5, cds_min = 0)) %>%
  mutate(cds_mph = (cds_min/segment_dur)*60) %>%
  arrange(aclew_child_id, segment)
# Number of speakers per clip
spkrs.per.seg.rand <- all.data %>%
  filter(sample == "random" & speaker != "CHI" &
           !(grepl("@", tier))) %>%
  group_by(aclew_child_id, segment) %>%
  summarise(n_spkrs_clip = length(unique(speaker)))
# All together
quantity.rand <- xds.per.seg.rand %>%
  full_join(ods.per.seg.rand, by = c("aclew_child_id", "segment", "segment_dur")) %>%
  full_join(tds.per.seg.rand, by = c("aclew_child_id", "segment", "segment_dur")) %>%
  full_join(cds.per.seg.rand, by = c("aclew_child_id", "segment", "segment_dur")) %>%
  full_join(spkrs.per.seg.rand, by = c("aclew_child_id", "segment")) %>%
  left_join(dplyr::select(seg.info, c("aclew_id", "CodeName", "start.hr")),
            by = c("aclew_child_id" = "aclew_id", "segment" = "CodeName")) %>%
  full_join(ptcp.info, by = "aclew_child_id") %>%
  replace_na(list(xds_min = 0, xds_mph = 0,
                  tds_min = 0, tds_mph = 0,
                  ods_min = 0, ods_mph = 0,
                  cds_min = 0, cds_mph = 0,
                  n_spkrs_clip = 0)) %>%
  mutate(prop_tds = tds_min/xds_min)
  # Don't replace NAs with 0s in this case; proportion is not meaningful w/o any speech
quantity.rand.bychild <- quantity.rand %>%
  group_by(aclew_child_id) %>%
  summarise(
    xds_min = mean(xds_min),
    xds_mph = mean(xds_mph),
    ods_min = mean(ods_min),
    ods_mph = mean(ods_mph),
    tds_min = mean(tds_min),
    tds_mph = mean(tds_mph),
    cds_min = mean(cds_min),
    cds_mph = mean(cds_mph),
    prop_tds = mean(prop_tds, na.rm = TRUE),
    m_n_spkrs = mean(n_spkrs_clip)) %>%
  full_join(ptcp.info, by = "aclew_child_id")

# Get xds and tds min/hr by speaker type
all.data$SpkrAge <- "Not known"
all.data$SpkrAge[grepl("FA|MA|UA", all.data$speaker)] <- "Adult"
all.data$SpkrAge[grepl("FC|MC|UC", all.data$speaker)] <- "Child"
all.rand.segments.sa <- tibble(
  aclew_child_id = rep(unique(all.data$aclew_child_id),
                2*n.unique.rand.segs),
  segment = rep(unique(all.data$segment[grepl("random", all.data$segment)]),
                2*n.unique.recs),
  SpkrAge = c(rep("Adult", (n.unique.rand.segs * n.unique.recs)),
              rep("Child", (n.unique.rand.segs * n.unique.recs))))
# XDS
xds.per.seg.rand.sa <- all.data %>%
  filter(sample == "random" & speaker != "CHI" & SpkrAge != "Not known" &
           grepl("xds@", tier)) %>%
  group_by(aclew_child_id, SpkrAge, segment, segment_dur) %>%
  summarise(xds_min.sa = round(sum(dur)/60000,3)) %>%
  full_join(all.rand.segments.sa, by = c("aclew_child_id", "segment", "SpkrAge")) %>%
  replace_na(list(segment_dur = 2.5, xds_min.sa = 0)) %>%
  mutate(xds_mph.sa = (xds_min.sa/segment_dur)*60) %>%
  arrange(aclew_child_id, segment, SpkrAge)
# ODS
ods.per.seg.rand.sa <- all.data %>%
  filter(sample == "random" & speaker != "CHI" & SpkrAge != "Not known" &
           grepl("xds@", tier) & val != "T") %>%
  group_by(aclew_child_id, SpkrAge, segment, segment_dur) %>%
  summarise(ods_min.sa = round(sum(dur)/60000,3)) %>%
  full_join(all.rand.segments.sa, by = c("aclew_child_id", "segment", "SpkrAge")) %>%
  replace_na(list(segment_dur = 2.5, ods_min.sa = 0)) %>%
  mutate(ods_mph.sa = (ods_min.sa/segment_dur)*60) %>%
  arrange(aclew_child_id, segment, SpkrAge)
# TDS
tds.per.seg.rand.sa <- all.data %>%
  filter(sample == "random" & speaker != "CHI" & SpkrAge != "Not known" &
           grepl("xds@", tier) & val == "T") %>%
  group_by(aclew_child_id, SpkrAge, segment, segment_dur) %>%
  summarise(tds_min.sa = round(sum(dur)/60000,3)) %>%
  full_join(all.rand.segments.sa, by = c("aclew_child_id", "segment", "SpkrAge")) %>%
  replace_na(list(segment_dur = 2.5, tds_min.sa = 0)) %>%
  mutate(tds_mph.sa = (tds_min.sa/segment_dur)*60) %>%
  arrange(aclew_child_id, segment, SpkrAge)
# All CDS
cds.per.seg.rand.sa <- all.data %>%
  filter(sample == "random" & speaker != "CHI" & SpkrAge != "Not known" &
           grepl("xds@", tier) & (val == "T" | val == "C")) %>%
  group_by(aclew_child_id, SpkrAge, segment, segment_dur) %>%
  summarise(cds_min.sa = round(sum(dur)/60000,3)) %>%
  full_join(all.rand.segments.sa, by = c("aclew_child_id", "segment", "SpkrAge")) %>%
  replace_na(list(segment_dur = 2.5, cds_min.sa = 0)) %>%
  mutate(cds_mph.sa = (cds_min.sa/segment_dur)*60) %>%
  arrange(aclew_child_id, segment, SpkrAge)
# Number of speakers per clip
spkrs.per.seg.rand.sa <- all.data %>%
  filter(sample == "random" & speaker != "CHI" & SpkrAge != "Not known" &
           !(grepl("@", tier))) %>%
  group_by(aclew_child_id, SpkrAge, segment) %>%
  summarise(n_spkrs_clip = length(unique(speaker)))
# All together
quantity.rand.sa <- xds.per.seg.rand.sa %>%
  full_join(ods.per.seg.rand.sa, by = c("aclew_child_id", "SpkrAge",
                                        "segment", "segment_dur")) %>%
  full_join(tds.per.seg.rand.sa, by = c("aclew_child_id", "SpkrAge",
                                        "segment", "segment_dur")) %>%
  full_join(cds.per.seg.rand.sa, by = c("aclew_child_id", "SpkrAge",
                                        "segment", "segment_dur")) %>%
  full_join(dplyr::select(quantity.rand, c("aclew_child_id", "segment", "tds_min")),
            by = c("aclew_child_id", "segment")) %>%
  full_join(spkrs.per.seg.rand.sa, by = c("aclew_child_id", "SpkrAge", "segment")) %>%
  left_join(dplyr::select(seg.info, c("aclew_id", "CodeName", "start.hr")),
            by = c("aclew_child_id" = "aclew_id", "segment" = "CodeName")) %>%
  full_join(ptcp.info, by = "aclew_child_id") %>%
  replace_na(list(xds_min.sa = 0, xds_mph.sa = 0,
                  ods_min.sa = 0, ods_mph.sa = 0,
                  tds_min.sa = 0, tds_mph.sa = 0,
                  cds_min.sa = 0, cds_mph.sa = 0,
                  n_spkrs_clip = 0)) %>%
  mutate(prop_tds.sa = tds_min.sa/xds_min.sa,
         prop_sa.tds = tds_min.sa/tds_min)
  # Don't replace NAs with 0s in this case; proportion is not meaningful w/o any speech
quantity.rand.bychild.sa <- quantity.rand.sa %>%
  group_by(aclew_child_id, SpkrAge) %>%
  summarise(
    xds_min.sa = mean(xds_min.sa),
    xds_mph.sa = mean(xds_mph.sa),
    ods_min.sa = mean(ods_min.sa),
    ods_mph.sa = mean(ods_mph.sa),
    tds_min.sa = mean(tds_min.sa),
    tds_mph.sa = mean(tds_mph.sa),
    cds_min.sa = mean(cds_min.sa),
    cds_mph.sa = mean(cds_mph.sa),
    prop_tds.sa = mean(prop_tds.sa, na.rm = TRUE),
    prop_sa.tds = mean(prop_sa.tds, na.rm = TRUE),
    m_n_spkrs = mean(n_spkrs_clip)) %>%
  full_join(ptcp.info, by = "aclew_child_id")


## Get variables ready for modeling
# random sample
quantity.rand$child_sex <- as.factor(quantity.rand$child_sex)
quantity.rand$mat_ed <- as.factor(quantity.rand$mat_ed)
nspkrs.m <- mean(quantity.rand$n_spkrs_clip)
nspkrs.sd <- sd(quantity.rand$n_spkrs_clip)
quantity.rand <- quantity.rand %>%
  mutate(
    xds_mph.nz = ifelse(xds_mph > 0, 1, 0),
    ods_mph.nz = ifelse(ods_mph > 0, 1, 0),
    tds_mph.nz = ifelse(tds_mph > 0, 1, 0),
    cds_mph.nz = ifelse(cds_mph > 0, 1, 0),
    tchiyr.std = ((age_mo_round - tchiyr.m)/tchiyr.sd),
    chisx.std = recode_factor(child_sex,
                              "M" = "M", "F" = "F"),
    mated.std = recode_factor(mat_ed,
                              "none" = "none", "primary" = "primary",
                              "secondary" = "secondary", "preparatory" = "preparatory"),
    mated.bin = recode_factor(mat_ed,
                              "none" = "0-5", "primary" = "0-5",
                              "secondary" = "6+", "preparatory" = "6+"),
    motyr.std = ((mother_age - motyr.m)/motyr.sd),
    nsb.std = ((number_older_sibs - nsb.m)/nsb.sd),
    hsz.std = ((household_size - hsz.m)/hsz.sd),
    nsk.std = ((n_spkrs_clip - nspkrs.m)/nspkrs.sd),
    stthr.std = (start.hr - 12)/12)

quantity.rand.sa$child_sex <- as.factor(quantity.rand.sa$child_sex)
quantity.rand.sa$mat_ed <- as.factor(quantity.rand.sa$mat_ed)
nspkrs.sa.m <- mean(quantity.rand.sa$n_spkrs_clip)
nspkrs.sa.sd <- sd(quantity.rand.sa$n_spkrs_clip)
quantity.rand.sa <- quantity.rand.sa %>%
  mutate(
    xds_mph.sa.nz = ifelse(xds_mph.sa > 0, 1, 0),
    ods_mph.sa.nz = ifelse(ods_mph.sa > 0, 1, 0),
    tds_mph.sa.nz = ifelse(tds_mph.sa > 0, 1, 0),
    cds_mph.sa.nz = ifelse(cds_mph.sa > 0, 1, 0),
    tchiyr.std = ((age_mo_round - tchiyr.m)/tchiyr.sd),
    chisx.std = recode_factor(child_sex,
                              "M" = "M", "F" = "F"),
    mated.std = recode_factor(mat_ed,
                              "none" = "none", "primary" = "primary",
                              "secondary" = "secondary", "preparatory" = "preparatory"),
    mated.bin = recode_factor(mat_ed,
                              "none" = "0-5", "primary" = "0-5",
                              "secondary" = "6+", "preparatory" = "6+"),
    motyr.std = ((mother_age - motyr.m)/motyr.sd),
    nsb.std = ((number_older_sibs - nsb.m)/nsb.sd),
    hsz.std = ((household_size - hsz.m)/hsz.sd),
    nsk.std = ((n_spkrs_clip - nspkrs.sa.m)/nspkrs.sa.sd),
    stthr.std = (start.hr - 12)/12)


# overall
tds.rand.zinb <- glmmTMB(round(tds_mph,0) ~
                           tchiyr.std +
                           I(stthr.std^2) +
                           hsz.std +
                           nsk.std +
                           tchiyr.std:I(stthr.std^2) +
                           tchiyr.std:hsz.std +
                           tchiyr.std:nsk.std +
                           (1|aclew_child_id), #I(stthr.std^2)
                         data=quantity.rand,
                         ziformula=~tchiyr.std,#nsk.std,I(stthr.std^2)
                         family="nbinom1")
#res = simulateResiduals(tds.rand.zinb)
#plot(res, rank = T)
#summary(tds.rand.zinb)
# no significant effects at all

ods.rand.zinb <- glmmTMB(round(ods_mph,0) ~
                           tchiyr.std +
                           I(stthr.std^2) +
                           hsz.std +
                           nsk.std +
                           tchiyr.std:I(stthr.std^2) +
                           tchiyr.std:hsz.std +
                           tchiyr.std:nsk.std +
                           (1|aclew_child_id), #I(stthr.std^2)
                         data=quantity.rand,
                         ziformula=~nsk.std,#tchiyr.std,#nsk.std,I(stthr.std^2)
                         family="nbinom1")
#res = simulateResiduals(ods.rand.zinb)
#plot(res, rank = T)
#summary(ods.rand.zinb)



# by speaker type
tds.rand.zinb.sa <- glmmTMB(round(tds_mph.sa,0) ~
                           tchiyr.std +
                           I(stthr.std^2) +
                           SpkrAge +
                           hsz.std +
                           nsk.std +
                           tchiyr.std:I(stthr.std^2) +
                           tchiyr.std:SpkrAge +
                           tchiyr.std:hsz.std +
                           tchiyr.std:nsk.std +
                           (1|aclew_child_id), #I(stthr.std^2)
                         data=quantity.rand.sa,
                         ziformula=~tchiyr.std,#nsk.std,I(stthr.std^2)
                         family="nbinom1")
#res = simulateResiduals(tds.rand.zinb.sa)
#plot(res, rank = T)
#summary(tds.rand.zinb.sa)




# random
propchitcds.rand <- subset(quantity.rand.sa[
  which(!is.na(quantity.rand.sa$prop_sa.tds)),],
  SpkrAge == "Child")
propchitcds.rand.corr_age <- propchitcds.rand %>%
  group_by(aclew_child_id, age_mo_round) %>%
  summarise(avg_prpchitcds = mean(prop_sa.tds))
propchitcds.rand.corr_age.test <- cor.test(
  ~ age_mo_round + avg_prpchitcds,
  data = propchitcds.rand.corr_age, method = "spearman")


# ODS min/hr
odsmph.segments.rand.1 <- ggplot(quantity.rand,
                          aes(x = age_mo_round, y = ods_mph)) +
  geom_boxplot(aes(group = age_mo_round), fill = "gray50", color = "white",
               outlier.shape = NA,
               lty = "solid") +
  geom_smooth(fill = "white", color = "white", method = "lm") +
  ylab("ODS (min/hr)") + xlab("Child age (mo)")	+
  scale_y_continuous(limits=c(-10,80),
                     breaks=seq(0,80,20)) +
  scale_x_continuous(limits=c(0,38),
                     breaks=seq(0,38,6)) +
  coord_cartesian(ylim=c(0,80),xlim=c(0,38)) +
  theme_apa() +
  basic.theme + theme(
		panel.grid.major = element_blank(),
		panel.grid.minor = element_blank(),
		axis.text.x = element_text(color="white"),
	  axis.title.x = element_text(color="white"),
	  axis.text.y = element_text(color="white"),
	  axis.title.y = element_text(color="white"),
	  strip.text = element_text(color="white"),
		axis.ticks = element_line(color = "white"),
		axis.line = element_line(color="white", size = 0.4),
		legend.position = "none")

png(paste("diff-figs/","ods.1.png", sep=""),
    width=500, height=400,units="px", bg = "transparent")
print(odsmph.segments.rand.1)
dev.off()


# TDS min/hr - zoomed in
tdsmph.segments.rand <- ggplot(quantity.rand,
                          aes(x = age_mo_round, y = tds_mph)) +
  geom_boxplot(aes(group = age_mo_round), fill = "gray50", color = "white",
#  geom_boxplot(aes(group = age_mo_round), fill = "gray", color = "black",
               outlier.shape = NA,
               lty = "solid") +
  geom_smooth(fill = "white", color = "white", method = "lm") +
#  geom_smooth(fill = "gray", color = "black", method = "lm") +
  ylab("TCDS (min/hr)") + xlab("Child age (mo)")	+
  scale_y_continuous(limits=c(0,40),
                     breaks=seq(0,40,10)) +
  scale_x_continuous(limits=c(0,38),
                     breaks=seq(0,38,6)) +
  coord_cartesian(ylim=c(0,40),xlim=c(0,38)) +
  theme_apa() +
  basic.theme + theme(
		panel.grid.major = element_blank(),
		panel.grid.minor = element_blank(),
		axis.text.x = element_text(color="white"),
	  axis.title.x = element_text(color="white"),
	  axis.text.y = element_text(color="white"),
	  axis.title.y = element_text(color="white"),
	  strip.text = element_text(color="white"),
		axis.ticks = element_line(color = "white"),
		axis.line = element_line(color="white", size = 0.4),
		legend.position = "none")

png(paste("diff-figs/","tcds.1.png", sep=""),
    width=500, height=400,units="px", bg = "transparent")
print(tdsmph.segments.rand)
dev.off()

quantity.rand$Sample <- "random"

tod.tcds.1 <- ggplot(data = quantity.rand) +
  geom_point(data = quantity.rand, color = "white",
             aes(y = round(tds_mph,0), x = start.hr,
                 group = as.factor(ifelse(age_mo_round < 13, -1, 1)))) +
  geom_smooth(data = quantity.rand, color = "white", fill = "white",
              aes(y = round(tds_mph,0), x = start.hr,
                  group = as.factor(ifelse(age_mo_round < 13, -1, 1))),
              method = "lm", formula = y ~ poly(x, 2)) +
  facet_grid(~ as.factor(ifelse(age_mo_round < 13, "<13mo", "13+mo"))) +
  ylab("TCDS (min/hr)") + xlab("Time of day (hour)")	+
  scale_y_continuous(limits=c(-10,40),
                     breaks=c(0,10,20, 30, 40)) +
  scale_x_continuous(limits=c(8,18),
                     breaks=seq(8,18,2)) +
  coord_cartesian(ylim=c(0,40),xlim=c(8,18)) +
  theme_apa() +
  basic.theme + theme(
		panel.grid.major = element_blank(),
		panel.grid.minor = element_blank(),
		axis.text.x = element_text(color="white"),
	  axis.title.x = element_text(color="white"),
	  axis.text.y = element_text(color="white"),
	  axis.title.y = element_text(color="white"),
	  strip.text = element_text(color="white"),
		axis.ticks = element_line(color = "white"),
		axis.line = element_line(color="white", size = 0.4),
		legend.position = "none")

png(paste("diff-figs/","tcds-tod.1.png", sep=""),
    width=1000, height=400,units="px", bg = "transparent")
print(tod.tcds.1)
dev.off()

write_csv(quantity.rand, "quantity.rand.YD.csv")


### TSELTAL
quantity.rand.TS <- read_csv("quantity.rand.Ts.csv")
quantity.rand.sa.TS <- read_csv("quantity.rand.sa.Ts.csv")

quantity.rand.bychild.TS <- quantity.rand.TS %>%
  group_by(aclew_child_id) %>%
  summarise(
    xds_min = mean(xds_min),
    xds_mph = mean(xds_mph),
    ods_min = mean(ods_min),
    ods_mph = mean(ods_mph),
    tds_min = mean(tds_min),
    tds_mph = mean(tds_mph),
    cds_min = mean(cds_min),
    cds_mph = mean(cds_mph),
    prop_tds = mean(prop_tds, na.rm = TRUE),
    m_n_spkrs = mean(n_spkrs_clip))

quantity.rand.bychild.sa.TS <- quantity.rand.sa.TS %>%
  group_by(aclew_child_id, SpkrAge) %>%
  summarise(
    xds_min.sa = mean(xds_min.sa),
    xds_mph.sa = mean(xds_mph.sa),
    ods_min.sa = mean(ods_min.sa),
    ods_mph.sa = mean(ods_mph.sa),
    tds_min.sa = mean(tds_min.sa),
    tds_mph.sa = mean(tds_mph.sa),
    cds_min.sa = mean(cds_min.sa),
    cds_mph.sa = mean(cds_mph.sa),
    prop_tds.sa = mean(prop_tds.sa, na.rm = TRUE),
    prop_sa.tds = mean(prop_sa.tds, na.rm = TRUE),
    m_n_spkrs = mean(n_spkrs_clip))


# overall
tds.rand.zinb.ts <- glmmTMB(round(tds_mph,0) ~
                           tchiyr.std +
                           I(stthr.std^2) +
                           hsz.std +
                           nsk.std +
                           tchiyr.std:I(stthr.std^2) +
                           tchiyr.std:hsz.std +
                           tchiyr.std:nsk.std +
                           (1|aclew_child_id), #I(stthr.std^2)
                         data=quantity.rand.TS,
                         ziformula=~tchiyr.std,#nsk.std,I(stthr.std^2)
                         family="nbinom1")
#res = simulateResiduals(tds.rand.zinb.ts)
#plot(res, rank = T)
#summary(tds.rand.zinb.ts)
#I(stthr.std^2)              4.3219     1.9170   2.254   0.02417 *  
#nsk.std                     0.2440     0.1346   1.813   0.06982 .  
#tchiyr.std:I(stthr.std^2)  -5.2174     1.9739  -2.643   0.00821 ** 
#ZI
#tchiyr.std    -7.772      4.161  -1.868   0.0618 .

# by speaker type
tds.rand.zinb.sa.ts <- glmmTMB(round(tds_mph.sa,0) ~
                           tchiyr.std +
                           I(stthr.std^2) +
                           SpkrAge +
                           hsz.std +
                           nsk.std +
                           tchiyr.std:I(stthr.std^2) +
                           tchiyr.std:SpkrAge +
                           tchiyr.std:hsz.std +
                           tchiyr.std:nsk.std +
                           (1|aclew_child_id), #I(stthr.std^2)
                         data=quantity.rand.sa.TS,
                         ziformula=~tchiyr.std,#nsk.std,I(stthr.std^2)
                         family="nbinom1")
#res = simulateResiduals(tds.rand.zinb.sa.ts)
#plot(res, rank = T)
#summary(tds.rand.zinb.sa.ts)
#I(stthr.std^2)             3.65679    1.86689   1.959    0.05014 .  
#SpkrAgeChild              -1.44553    0.30335  -4.765 0.00000189 ***
#nsk.std                    0.32309    0.12087   2.673    0.00752 ** 
#tchiyr.std:I(stthr.std^2) -4.17561    1.97464  -2.115    0.03446 *  
#ZI
#tchiyr.std    -6.613      3.910  -1.692   0.0907 .

# TDS min/hr - zoomed in
tdsmph.segments.rand.ts <- ggplot(quantity.rand.TS,
                          aes(x = age_mo_round, y = tds_mph)) +
#  geom_boxplot(aes(group = age_mo_round), fill = "gray80", color = "white",
  geom_boxplot(aes(group = age_mo_round), fill = "gray", color = "black",
               outlier.shape = NA,
               lty = "solid") +
#  geom_smooth(fill = "white", color = "white", method = "lm") +
  geom_smooth(fill = "gray", color = "black", method = "lm") +
  ylab("TCDS (min/hr)") + xlab("Child age (mo)")	+
  scale_y_continuous(limits=c(0,40),
                     breaks=seq(0,40,10)) +
  scale_x_continuous(limits=c(0,38),
                     breaks=seq(0,38,6)) +
  coord_cartesian(ylim=c(0,40),xlim=c(0,38)) +
  theme_apa() +
  basic.theme + theme(
		panel.grid.major = element_blank(),
		panel.grid.minor = element_blank(),
#		axis.text.x = element_text(color="white"),
#	  axis.title.x = element_text(color="white"),
#	  axis.text.y = element_text(color="white"),
#	  axis.title.y = element_text(color="white"),
#	  strip.text = element_text(color="white"),
#		axis.ticks = element_line(color = "white"),
		axis.line = element_line(size = 0.4), #color="white"
		legend.position = "none")

png(paste("diff-figs/","tcds.1.ts.png", sep=""),
    width=500, height=400,units="px", bg = "transparent")
print(tdsmph.segments.rand.ts)
dev.off()

quantity.rand.TS$Sample <- "random"

tod.tcds.1.ts <- ggplot(data = quantity.rand.TS) +
  geom_point(data = quantity.rand.TS, color = "black",
             aes(y = round(tds_mph,0), x = start.hr)) +
  geom_smooth(data = quantity.rand.TS, color = "black", fill = "gray",
              aes(y = round(tds_mph,0), x = start.hr),
              method = "lm", formula = y ~ poly(x, 2)) +
#  facet_grid(~ as.factor(ifelse(age_mo_round < 13, "<13mo", "13+mo"))) +
  ylab("TCDS (min/hr)") + xlab("Time of day (hour)")	+
  scale_y_continuous(limits=c(-10,20),
                     breaks=c(0,5,10,15,20)) +
  scale_x_continuous(limits=c(8,18),
                     breaks=seq(8,18,2)) +
  coord_cartesian(ylim=c(0,20),xlim=c(8,18)) +
  theme_apa() +
  basic.theme + theme(
		panel.grid.major = element_blank(),
		panel.grid.minor = element_blank(),
#		axis.text.x = element_text(color="white"),
#	  axis.title.x = element_text(color="white"),
#	  axis.text.y = element_text(color="white"),
#	  axis.title.y = element_text(color="white"),
#	  strip.text = element_text(color="white"),
#		axis.ticks = element_line(color = "white"),
		axis.line = element_line(size = 0.4), #color="white"
		legend.position = "none")

png(paste("diff-figs/","tcds-tod.1.ts.png", sep=""),
    width=500, height=400,units="px", bg = "transparent")
print(tod.tcds.1.ts)
dev.off()

######
quantity.rand$site <- "Yélî"
quantity.rand.TS$site <- "Tseltal"
quantity.rand$aclew_child_id <- as.character(quantity.rand$aclew_child_id)
quantity.rand.all <- bind_rows(quantity.rand, quantity.rand.TS)

# TDS min/hr - zoomed in
tdsmph.segments.rand.all <- ggplot(quantity.rand.all,
                          aes(x = age_mo_round, y = tds_mph, group = site)) +
#  geom_boxplot(aes(group = age_mo_round), fill = "gray80", color = "white",
  geom_boxplot(aes(group = age_mo_round), fill = "gray", color = "black",
               outlier.shape = NA,
               lty = "solid") +
#  geom_smooth(fill = "white", color = "white", method = "lm") +
  geom_smooth(fill = "gray", color = "black", method = "lm") +
  ylab("TCDS (min/hr)") + xlab("Child age (mo)")	+
  facet_grid(. ~ site) +
  scale_y_continuous(limits=c(0,20),
                     breaks=seq(0,20,5)) +
  scale_x_continuous(limits=c(0,38),
                     breaks=seq(0,38,6)) +
  coord_cartesian(ylim=c(0,20),xlim=c(0,38)) +
  theme_apa() +
  basic.theme + theme(
		panel.grid.major = element_blank(),
		panel.grid.minor = element_blank(),
#		axis.text.x = element_text(color="white"),
#	  axis.title.x = element_text(color="white"),
#	  axis.text.y = element_text(color="white"),
#	  axis.title.y = element_text(color="white"),
#	  strip.text = element_text(color="white"),
#		axis.ticks = element_line(color = "white"),
		axis.line = element_line(size = 0.4), #color="white"
		legend.position = "none")

png(paste("diff-figs/","tcds.1.all.png", sep=""),
    width=1000, height=400,units="px", bg = "transparent")
print(tdsmph.segments.rand.all)
dev.off()

quantity.rand.all$AgeGroup <- ifelse(quantity.rand.all$age_mo_round < 13, " < 1;1", " 1;1+")

tod.tcds.1.all <- ggplot(data = quantity.rand.all) +
  geom_point(data = quantity.rand.all,
             aes(y = round(tds_mph,0), x = start.hr,
                 color = AgeGroup)) +
  geom_smooth(data = quantity.rand.all,
              aes(y = round(tds_mph,0), x = start.hr,
                  color = AgeGroup, fill = AgeGroup),
              method = "lm", formula = y ~ poly(x, 2)) +
  ylab("TCDS (min/hr)") + xlab("Time of day (hour)")	+
  facet_grid(. ~ site) +
  scale_y_continuous(limits=c(-10,20),
                     breaks=c(0,5,10,15,20)) +
  scale_x_continuous(limits=c(8,18),
                     breaks=seq(8,18,2)) +
  scale_colour_manual(values = c("gray60", "gray20")) +
  scale_fill_manual(values = c("gray60", "gray20")) +
  coord_cartesian(ylim=c(0,20),xlim=c(8,18)) +
  theme_apa() +
  basic.theme + theme(
		panel.grid.major = element_blank(),
		panel.grid.minor = element_blank(),
#		axis.text.x = element_text(color="white"),
#	  axis.title.x = element_text(color="white"),
#	  axis.text.y = element_text(color="white"),
#	  axis.title.y = element_text(color="white"),
#	  strip.text = element_text(color="white"),
#		axis.ticks = element_line(color = "white"),
		axis.line = element_line(size = 0.4), #color="white"
    strip.text.x = element_text(size = 40),
		legend.position = "right")

png(paste("diff-figs/","tcds-tod-all.png", sep=""),
    width=1000, height=400,units="px", bg = "transparent")
print(tod.tcds.1.all)
dev.off()