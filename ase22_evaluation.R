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
read_satisfiable = FALSE

if (!exists("analyze")) {
  # read CSV files
  transform = read_csv("results_transform.csv", col_type="cncnnncnnn")
  analyze = read_csv("results_analyze.csv",
                     col_type=if(read_satisfiable) "cnccccnlc" else "cnccccnc")
  if (!read_satisfiable) analyze$satisfiable = TRUE
  
  # discard iterations by taking the median and join tables
  transform = aggregate(
    cbind(extract_time, extract_variables, extract_literals, transform_time,
          transform_variables, transform_literals) ~
      system + source + transformation,
    data=transform, median, na.action=na.pass)
  analyze = merge(
    merge(
      aggregate(solve_time ~ system + source + transformation + solver + analysis,
                data=analyze, median, na.action=na.pass),
      aggregate(satisfiable ~ system + source + transformation + solver + analysis,
                data=analyze, median, na.action=na.pass)),
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
  data$analysis_short = ifelse(
    data$analysis_short == "Core" | data$analysis_short == "Dead",
    "Core/Dead",
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
    mutate(model_count_1=
             `if`(is.true(as.bigz(model_count[transformation == baseline]) > 0),
                  as.character(as.bigz(model_count)/
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
  outliers = function(data, c, x, test=is.na, label="") {
    outliers = merge(
      data %>% count(!!sym(x)) %>% rename(nall=n),
      foutliers(data, c, test) %>%
        count(!!sym(x)) %>% rename(nfail=n), all=TRUE)
    outliers[is.na(outliers)] = 0
    outliers$label =
      sprintf("%s %s",
              scales::percent((outliers$nall-outliers$nfail)/outliers$nall),
              label)
    outliers$color = "black"
    return(outliers)
  }
  outliers_2dim = function(data, c, test=is.na, label="") {
    outliers = merge(
      data %>% count(transformation, analysis_short) %>% rename(nall=n),
      foutliers(data, c, test) %>%
        count(transformation, analysis_short) %>% rename(nfail=n), all=TRUE)
    outliers[is.na(outliers)] = 0
    outliers$label = scales::percent(
      (outliers$nall-outliers$nfail)/outliers$nall, accuracy=0.1)
    outliers$color = "black"
    return(outliers)
  }
  transform_data = fdata() %>%
    distinct(system, source, transformation, transform_time, transform_time_rel,
             transform_variables, transform_variables_rel,
             transform_literals, transform_literals_rel)
  transform_data$analysis_short = "Transformation"
  transform_data$solve_time_rel = transform_data$transform_time_rel
  time_data = union_all(
    fdata() %>% select(transformation, analysis_short, solve_time_rel),
    transform_data %>% select(transformation, analysis_short, solve_time_rel)) %>%
    rename(time="solve_time_rel")
}

# failed to relate solve time / model count to baseline for this data
data[which(data$solve_time_fail | data$model_count_fail),]

# failed to determine satisfiability / model count
fdata("", "sat") %>% filter(!is.na(transform_time)) %>% nrow()
fdata("", "sat") %>% filter(!is.na(transform_time) & !is.na(satisfiable)) %>% nrow()
fdata("", "sharpsat") %>% filter(!is.na(transform_time)) %>% nrow()
fdata("", "sharpsat") %>% filter(!is.na(transform_time) & !is.na(model_count)) %>% nrow()

# satisfiability/model count does not match for this data
data %>%
  group_by(system, source, solver, analysis) %>%
  mutate(satisfiability_equal=satisfiable == satisfiable[transformation == baseline]) %>%
  ungroup() %>%
  filter(satisfiability_equal==FALSE)
fdata("", "sharpsat") %>% filter(!is.na(transform_time) & !is.na(model_count)) %>%
  group_by(system, source, solver, analysis) %>%
  mutate(mce=if(length(model_count[transformation == baseline])==0) TRUE
         else model_count == model_count[transformation == baseline]) %>%
  mutate(mc=paste(model_count, model_count[transformation == baseline])) %>%
  filter(transformation == "KConfigReader" & mce==FALSE) 
data %>% filter(transformation == "KConfigReader" &
                  (model_count_1) != "NA" & model_count_rel > 1 & analysis_short == "FC") %>%
  select(system,source,solver,analysis,model_count_rel,model_count_1) %>%
  summarize(min=min(model_count_rel),max=max(model_count_rel),median=median(model_count_rel))

# median of transformation runtimes
merge(data, data %>% filter(transformation=="FeatureIDE" & !is.na(transform_time)) %>%
        select(system, source) %>% distinct()) %>%
  group_by(transformation) %>%
  summarise(median=median(transform_time, na.rm=TRUE))

# quartiles of solver runtimes
data %>% group_by(transformation) %>%
  summarise(median=median(solve_time_rel, na.rm=TRUE),
            iqr=IQR(solve_time_rel, na.rm=TRUE),
            q1=quantile(solve_time_rel, na.rm=TRUE)[1],
            q2=quantile(solve_time_rel, na.rm=TRUE)[2],
            q4=quantile(solve_time_rel, na.rm=TRUE)[4],
            q5=quantile(solve_time_rel, na.rm=TRUE)[5])

# Z3 fastest
fast = function(t) {
  (merge(data, fdata("", "") %>%
           group_by(system, source, solver, analysis) %>%
           summarise(min=min(solve_time, na.rm=TRUE), .groups="keep") %>%
           ungroup()) %>%
     filter(transformation==t&min==solve_time) %>%
     nrow()) /
    (merge(data, fdata("", "") %>%
             group_by(system, source, solver, analysis) %>%
             summarise(min=min(solve_time, na.rm=TRUE), .groups="keep") %>%
             ungroup()) %>%
       filter(transformation==t&!is.infinite(min)) %>%
       nrow())
}
fast("Z3") + fast("FeatureIDE") + fast("KConfigReader")

# serialize data
dir.create("results", showWarnings=FALSE)
write.table(data, file = "results/data.csv")
write.table(transform_data, file = "results/transform_data.csv")

# perform significance tests
sig_test = function(dataset, model) {
	res = merge(
		t_test(dataset, model, paired = TRUE),
		cohens_d(dataset, model, paired = TRUE))
	res = select(res, c("group1","group2","p.adj","effsize"))
	res = rename(res, T1 = group1, T2 = group2, "p-Value" = p.adj, "Effect Size" = effsize)
	m = unlist(str_split(deparse(model), " "))
	cat(sprintf("%s ~ %s\n", m[1], m[3]))
	print(res)
	cat("\n")
	print(xtable(res, type = "latex", digits=-2), file=sprintf("results/%s_%s.tex", m[1], m[3]))
}

# draw plots
logx = function(p) { p %>% ggpar(xscale="log10") }
logy = function(p) { p %>% ggpar(yscale="log10") }
labx = function(p, l) { p %>% ggpar(xlab=l) }
laby = function(p, l) { p %>% ggpar(ylab=l) }
plot = function(p, export=NA, width=7, height=4) { 
  p = p %>% ggpar(palette=palette)
  if (!is.na(export))
    p %>% ggexport(filename=sprintf("results/%s.pdf", export), width=width, height=height)
  p %>% print()
}
relative = function(p, y=1) { p %>%
    add(geom_hline(yintercept=y, linetype="dashed", size=0.3)) }
label = function(p, data, x, offset) { p %>%
    add(geom_text(data=data, color=data$color, fontface="italic",
                  aes(x=!!sym(x), y=offset, label=label))) }
add = ggplot2:::add_ggplot

# transformation time
if (0) melt(transform_data %>%
              rename("Transform Time"=transform_time_rel) %>%
              rename("#Variables"=transform_variables_rel) %>%
              rename("#Literals"=transform_literals_rel),
            id.vars = "transformation",
            measure.vars = c("Transform Time", "#Variables", "#Literals")) %>%
  ggboxplot(x="transformation", y="value", color="variable", outlier.shape=20, na.rm=TRUE) %>%
  relative() %>%
  label(outliers(transform_data, "transform_time", "transformation"), "transformation", 0.1) %>%
  logy() %>%
  labx("CNF Transformation Tool") %>%
  laby("Transform Time / Formula Size (log10, rel. to Z3)") %>%
  add(labs(color="")) %>%
  plot()

# solve time
if (0) for (s in c("sat", "sharpsat")) fdata("", s) %>%
  ggboxplot(x="transformation", y="solve_time_rel", color="analysis_short", outlier.shape=20, na.rm=TRUE) %>%
  relative() %>%
  label(outliers(fdata("", s), "solve_time", "transformation"), "transformation", if (s == "sat") 0.2 else 0.1) %>%
  logy() %>%
  labx("CNF Transformation Tool") %>%
  laby("Solve Time (log10, rel. to Z3)") %>%
  add(labs(color="Analysis")) %>%
  plot()

if(0) fdata("", "sat", "", TRUE) %>%
  ggscatter(x="extract_literals", y="solve_time_rel", color="transformation", na.rm=TRUE) %>%
  relative() %>%
  logy() %>%
  logx() %>%
  labx("Feature Model Size (log10, #Literals)") %>%
  laby("Solve Time (log10, rel. to Z3)") %>%
  add(labs(color="Transformation")) %>%
  plot()

# solve time by system
if (0) for (s in c("sat", "sharpsat")) fdata("", s, "void") %>%
  ggboxplot(x="transformation", y="solve_time_rel", outlier.shape=20, na.rm=TRUE) %>%
  relative() %>%
  facet(facet.by="system", scales="free_y") %>%
  logy() %>%
  plot()

# plot percentage of model size increase against solve time
if (0) for (solver in c("sat")) fdata("", solver, "", FALSE) %>%
  ggscatter(x="new_variables_rel", y="solve_time", color="transformation") %>%
  facet(facet.by = "solver") %>%
  plot()

# solve time by size
if (0)
  for (s in c("sat", "sharpsat")) fdata("", s, "", TRUE) %>%
  ggboxplot(x="extract_literals", y="solve_time_rel", color="transformation", outlier.shape=20, na.rm=TRUE) %>%
  add(geom_boxplot(data=fdata("", s, "", TRUE) %>% filter(is.na(solve_time_rel)) %>% mutate(solve_time_rel=25),
                   aes(x=as.factor(extract_literals), y=solve_time_rel, color=transformation), na.rm=TRUE)) %>%
  relative() %>%
  relative(y=25) %>%
  add(scale_x_discrete(labels = \(x) formatter(as.numeric(x)))) %>%
  logy() %>%
  labx("Feature Model Size (#Literals)") %>%
  laby("Solve Time (log10, rel. to Z3)") %>%
  add(labs(color="Transformation")) %>%
  add(rotate_x_text()) %>%
  plot(sprintf("rq2-%s", s))

# RQ1 and RQ2
time_data %>%
  filter(time < 1e+2) %>%
  ggboxplot(x="analysis_short", y="time", color="transformation", outlier.shape=20, na.rm=TRUE,
            order=c("Transformation", "Void", "Core/Dead", "FMC", "FC")) %>%
  relative() %>%
  add(geom_text(data=outliers_2dim(time_data, "time"), fontface="italic",
                aes(x=analysis_short, y=0.05, color=transformation, label=label), #angle=30),
                position=position_dodge(width=0.8), vjust=-1)) %>%
  add(geom_text(data=outliers_2dim(time_data, "time", \(x) x > 1e+2), fontface="italic",
                aes(x=analysis_short, y=1e+2, color=transformation, label=label), #angle=30),
                position=position_dodge(width=0.8), vjust=-1)) %>%
  add(geom_text(data=time_data, aes(x=analysis_short, y=160, fontface="italic", label="\n\n< 100"), check_overlap = TRUE)) %>%
  logy() %>%
  labx("Algorithm") %>%
  laby("Algorithm Runtime (log10, rel. to Z3)") %>%
  add(labs(color="CNF Transformation Tool")) %>%
  plot("rq12", 12, 5)

# model count correctness
fdata("", "sharpsat") %>%
  filter(model_count_rel < 1e+2) %>%
  arrange(transformation) %>%
  ggboxplot(x="transformation", y="model_count_rel", color="analysis_short", outlier.shape=20, na.rm=TRUE) %>%
  relative() %>%
  add(geom_text(data=fdata("", "sharpsat"), aes(x=transformation, y=0.4*1e+3, label=""))) %>%
  label(outliers(fdata("", "sharpsat") %>% filter(!is.na(model_count)), "model_count_rel", "transformation", \(x) x > 1e+2, "< 100"), "transformation", 0.3*1e+3) %>%
  logy() %>%
  labx("CNF Transformation Tool") %>%
  laby("Model Count (log10, rel. to Z3)") %>%
  add(labs(color="Analysis")) %>%
  plot("rq3", 6, 4)

sig_test(transform_data, transform_time ~ transformation)
sig_test(data, solve_time ~ transformation)