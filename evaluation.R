library(tidyverse) # plots, CSV import
library(ggpubr) # publication-ready plots
library(gmp) # process big model counts correctly
library(reshape2) # melt data
library(rstatix)
library(xtable)

# redraw plots, prevent scientific notation, use color-blind palette
graphics.off()
options(scipen=60)
palette = c("#000000", "#E69F00", "#56B4E9", "#009E73",
            "#F0E442", "#0072B2", "#D55E00", "#CC79A7")

# parameters
baseline = "Z3"
exclude_system = "toybox"

# read CSV files
transform = read_csv("results_transform.csv", col_type="cncnnncnnn")
analyze = read_csv("results_analyze.csv", col_type="cnccccnc")

# discard iterations by taking the median and join tables
transform = aggregate(
  cbind(extract_time, extract_variables, extract_literals, transform_time,
        transform_variables, transform_literals) ~
    system + source + transformation,
  data=transform, median, na.action=na.pass)
analyze = merge(
  aggregate(solve_time ~ system + source + transformation + solver + analysis,
  data=analyze, median, na.action=na.pass),
  aggregate(model_count ~ system + source + transformation + solver + analysis,
    data=analyze, median, na.action=na.pass))

data = merge(transform, analyze)

# better labels
formatter = scales::number_format(accuracy = 1, scale = 1/1000, suffix = "k")
data = data %>%
  mutate(transformation=
           str_replace(transformation, "featureide", "FeatureIDE")) %>%
  mutate(transformation=
           str_replace(transformation, "kconfigreader", "KConfigReader")) %>%
  mutate(transformation=
           str_replace(transformation, "z3", "Z3"))

# add columns
capitalize = function(c) {
  gsub("([\\w])([\\w]+)", "\\U\\1\\L\\2", c, perl=TRUE) }
#data$new_variables = data$transform_variables - data$extract_variables
#data$new_literals = data$transform_literals - data$extract_literals
#data$new_variables_rel = data$transform_variables / data$extract_variables
#data$new_literals_rel = data$transform_literals / data$extract_literals
data$system_long = paste(data$system, data$source)
data$system_short = str_split(data$system, "_") %>% map(1) %>% flatten_chr()
data$solver_short = str_split(data$solver, "-") %>% map(2) %>% flatten_chr()
data$analysis = str_split(data$analysis, "-") %>% map(1) %>% flatten_chr()
data$analysis_short = capitalize(
  str_split(data$analysis, "\\d") %>% map(1) %>% flatten_chr())
data$analysis_short = ifelse(
  startsWith(data$solver, "sharpsat"),
  ifelse(data$analysis_short == "Void", "FMC", "FC"),
  data$analysis_short)


# calculate solve time and model count relative to the baseline
is.true = function(x) { !is.na(x) & x }
data = data %>%
  group_by(system, source) %>%
  mutate(transform_time_rel=
           transform_time/transform_time[transformation == baseline]) %>%
  mutate(transform_variables_rel=
           transform_variables/transform_variables[transformation == baseline]) %>%
  mutate(transform_literals_rel=
           transform_literals/transform_literals[transformation == baseline]) %>%
  ungroup() %>%
  group_by(system, source, solver, analysis) %>%
  mutate(solve_time_rel=solve_time/solve_time[transformation == baseline]) %>%
  mutate(solve_time_fail=
           is.na(solve_time[transformation == baseline]) &&
           !is.na(solve_time)) %>%
  mutate(model_count_rel=
           `if`(is.true(as.bigz(model_count[transformation == baseline]) > 0),
             as.numeric(as.bigz(model_count)/
                          as.bigz(model_count[transformation == baseline])),
             NA)) %>%
  mutate(model_count_fail=
           !is.true(as.bigz(model_count[transformation == baseline]) > 0) &&
           is.true(as.bigz(model_count) > 0)) %>%
  ungroup()

# filter and preprocess data
data = data[which(!startsWith(data$system, exclude_system)),]
fdata = function(system="", solver="", analysis="", remove_baseline = FALSE) {
  data = data[which(startsWith(data$system, system)),]
  data = data[which(startsWith(data$solver, solver)),]
  data = data[which(startsWith(data$analysis, analysis)),]
  if (remove_baseline) data = data[which(data$transformation != baseline),]
  return(data)
}
foutliers = function(data, c, test) {
  data[which(test(pull(data, !!sym(c)))),] }

outliers = function(data, c, test=is.na, label="") {
  outliers = merge(
    data %>% count(transformation) %>% rename(nall=n),
    foutliers(data, c, test) %>%
      count(transformation) %>% rename(nfail=n), all=TRUE)
  outliers[is.na(outliers)] = 0
  outliers$label =
    sprintf("%s/%s (%s) %s", outliers$nall-outliers$nfail, outliers$nall,
            scales::percent((outliers$nall-outliers$nfail)/outliers$nall),
            label)
  #outliers$color = ifelse(outliers$nfail == 0, "black", "red")
  outliers$color = "black"
  return(outliers)
}

transform_data = fdata("", "", "", FALSE) %>%
  distinct(system, source, transformation, transform_time, transform_time_rel,
           transform_variables, transform_variables_rel,
           transform_literals, transform_literals_rel)

# failed to relate solve time / model count to baseline for this data
#data[which(data$solve_time_fail | data$model_count_fail),]

write.table(data , file = "data.csv")
write.table(transform_data , file = "transform_data.csv")

sig_test = function(dataset, model) {
	res = merge(
		t_test(dataset, model, paired = TRUE), 
		cohens_d(dataset, model, paired = TRUE))
	res = select(res, c("group1","group2","p.adj","effsize"))
	res = rename(res, T1 = group1, T2 = group2, "p-Value" = p.adj, "Effect Size" = effsize)
	
	m = unlist(str_split(deparse(model), " "))
	cat(paste("---------", m[1], "---------\n"))
	print(res)
	cat("\n")
	print(xtable(res, type = "latex", digits=5), file=paste(paste(m[1], m[3], sep="_"), ".tex", sep=""))
}

sig_test(transform_data, transform_time ~ transformation)
#sig_test(transform_data, transform_variables ~ transformation)
#sig_test(transform_data, transform_literals ~ transformation)
sig_test(data, solve_time ~ transformation)
#sig_test(data, model_count ~ transformation)

# draw plots
logx = function(p) { p %>% ggpar(xscale="log10") }
logy = function(p) { p %>% ggpar(yscale="log10") }
labx = function(p, l) { p %>% ggpar(xlab=l) }
laby = function(p, l) { p %>% ggpar(ylab=l) }
plot = function(p, export=NA) { 
  p = p %>% ggpar(palette=palette)
  if (!is.na(export))
    p %>% ggexport(filename=sprintf("%s.pdf", export), width=5, height=4)
  p %>% print()
}
relative_to_one = function(p) { p %>%
    add(geom_hline(yintercept=1, linetype="dashed", size=0.3)) }
label = function(p, data, x, offset) { p %>%
    add(geom_text(data=data, color=data$color, fontface="italic",
                  aes(x=!!sym(x), y=offset, label=label))) }
add = ggplot2:::add_ggplot

# RQ1: transformation time
if (0) melt(transform_data %>%
              rename("Transform Time"=transform_time_rel) %>%
              rename("#Variables"=transform_variables_rel) %>%
              rename("#Literals"=transform_literals_rel),
            id.vars = "transformation",
            measure.vars = c("Transform Time", "#Variables", "#Literals")) %>%
  ggboxplot(x="transformation", y="value", color="variable", outlier.shape=20, na.rm=TRUE) %>%
  relative_to_one() %>%
  label(outliers(transform_data, "transform_time"), "transformation", 0.1) %>%
  logy() %>%
  labx("CNF Transformation") %>%
  laby("Transform Time / Formula Size (log10, rel. to Z3)") %>%
  add(labs(color="")) %>%
  plot("rq1")

# RQ2: solve time
if (0) for (s in c("sat", "sharpsat")) fdata("", s) %>%
  ggboxplot(x="transformation", y="solve_time_rel", color="analysis_short", outlier.shape=20, na.rm=TRUE) %>%
  relative_to_one() %>%
  label(outliers(fdata("", s), "solve_time"), "transformation", if (s == "sat") 0.2 else 0.1) %>%
  add(stat_summary(fun.data=median_hilow)) %>%
  logy() %>%
  labx("CNF Transformation") %>%
  laby("Solve Time (log10, rel. to Z3)") %>%
  add(labs(color="Analysis")) %>%
  plot(sprintf("rq2-%s", s))

# RQ2: solve time by size (omit timeouts, which are already shown above)
if (0) for (s in c("sat", "sharpsat")) fdata("", s, "", TRUE) %>%
  ggboxplot(x="extract_literals", y="solve_time_rel", color="transformation", outlier.shape=20, na.rm=TRUE) %>%
  relative_to_one() %>%
  add(scale_x_discrete(labels = \(x) formatter(as.numeric(x)))) %>%
  #add(geom_text(aes(label=sprintf("%s (%s)", system_short, substr(source, 0, 3)), y=if (s == "sat") 25 else 300, angle=90, hjust="inward"), size=3)) %>%
  logy() %>%
  labx("Feature Model Size (#Literals)") %>%
  laby("Solve Time (log10, rel. to Z3)") %>%
  add(labs(color="Transformation")) %>%
  add(rotate_x_text()) %>%
  plot(sprintf("rq2a-%s", s))

# RQ3: model count correctness
if (1) fdata("", "sharpsat") %>%
  filter(model_count_rel < 1e+8) %>%
  arrange(transformation) %>%
  ggboxplot(x="transformation", y="model_count_rel", color="analysis_short", outlier.shape=20, na.rm=TRUE) %>%
  relative_to_one() %>%
  label(outliers(fdata("", "sharpsat") %>% filter(!is.na(solve_time)), "model_count_rel", \(x) x > 1e+8, "\n< 1e+8"), "transformation", 1e+6) %>%
  logy() %>%
  labx("CNF Transformation") %>%
  laby("Model Count (log10, rel. to Z3)") %>%
  add(labs(color="Analysis")) %>%
  plot("rq3")

# solve time by system
if (0) for (s in c("sat", "sharpsat")) fdata("", s, "void") %>%
  ggboxplot(x="transformation", y="solve_time_rel", outlier.shape=20, na.rm=TRUE) %>%
  relative_to_one() %>%
  facet(facet.by="system", scales="free_y") %>%
  logy() %>%
  plot()

# plot percentage of model size increase against solve time
if (0) for (solver in c("sat")) fdata("", solver, "", FALSE) %>%
  ggscatter(x="new_variables_rel", y="solve_time", color="transformation") %>%
  facet(facet.by = "solver") %>%
  plot()

# quantile((fdata("", "sat") %>% filter(transformation=="KConfigReader"))$solve_time_rel, na.rm=TRUE)
# fdata("", "sat") %>% filter(transformation=="Z3") %>% filter(is.na(solve_time) &!is.na(transform_time))
