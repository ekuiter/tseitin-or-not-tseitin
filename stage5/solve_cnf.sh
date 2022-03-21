#!/bin/bash
set -e

res=data/results_analyze.csv
err=data/error_analyze.log

run-solver() (
    log=data/$dimacs,$solver,$analysis.log
    echo "    Running solver $solver for analysis $analysis"
    start=`date +%s.%N`
    (timeout $TIMEOUT_ANALYZE ./$solver input.dimacs > $log) || true
    end=`date +%s.%N`
    if cat $log | grep -q "SATISFIABLE" || cat $log | grep -q "^s " || cat $log | grep -q " of solutions" || cat $log | grep -q "# solutions" || cat $log | grep -q " models"; then
        model_count=$(cat $log | sed -z 's/\n# solutions \n/SHARPSAT/g' | grep -oP "((?<=Counting...)\d+(?= models)|(?<=  Counting... )\d+(?= models)|(?<=c model count\.{12}: )\d+|(?<=^s )\d+|(?<=^s mc )\d+|(?<=#SAT \(full\):   		)\d+|(?<=SHARPSAT)\d+|(?<=Number of solutions\t\t\t)[.e+\-\d]+)" || true)
        model_count="${model_count:-NA}"
        echo $dimacs,$solver,$analysis,$(echo "($end - $start) * 1000000000 / 1" | bc),$model_count >> $res
    else
        echo "WARNING: No solver output for $dimacs with solver $solver and analysis $analysis" | tee -a $err
        echo $dimacs,$solver,$analysis,NA,NA >> $res
    fi
)

run-void-analysis() (
    cat $dimacs_path | grep -E "^[^c]" > input.dimacs
    echo "  Void feature model / feature model cardinality"
    run-solver
)

run-core-dead-analysis() (
    features=$(cat $dimacs_path | grep -E "^c [1-9]" | cut -d' ' -f2 | shuf --random-source=<(yes $RANDOM_SEED) | head -n$NUM_FEATURES)
    for f in $features; do
        echo "  $1 $f"
        cat $dimacs_path | grep -E "^[^c]" > input.dimacs
        clauses=$(cat input.dimacs | grep -E ^p | cut -d' ' -f4)
        clauses=$((clauses + 1))
        sed -i "s/^\(p cnf [[:digit:]]\+ \)[[:digit:]]\+/\1$clauses/" input.dimacs
        echo "$2$f 0" >> input.dimacs
        run-solver
    done
)

run-dead-analysis() (
    run-core-dead-analysis "Dead feature / feature cardinality" ""
)

run-core-analysis() (
    run-core-dead-analysis "Core feature" "-"
)

echo system,iteration,source,transformation,solver,analysis,solve_time >> $res
touch $err

for dimacs_path in data/dimacs/*.dimacs; do
    dimacs=$(basename $dimacs_path .dimacs | sed 's/,/_/')
    echo "Processing $dimacs"
    for solver in $SOLVERS; do
        for analysis in $ANALYSES; do
            if [[ $solver != sharpsat-* ]] || [[ $analysis != core ]]; then
                run-$analysis-analysis
            fi
        done
    done
done