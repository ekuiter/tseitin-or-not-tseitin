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
        satisfiable=$(cat $log | grep -q "^s SATISFIABLE$\|^SATISFIABLE$" && echo TRUE || (cat $log | grep -q "^s UNSATISFIABLE$\|^UNSATISFIABLE$" && echo FALSE || echo NA))
        model_count=$(cat $log | sed -z 's/\n# solutions \n/SHARPSAT/g' | grep -oP "((?<=Counting...)\d+(?= models)|(?<=  Counting... )\d+(?= models)|(?<=c model count\.{12}: )\d+|(?<=^s )\d+|(?<=^s mc )\d+|(?<=#SAT \(full\):   		)\d+|(?<=SHARPSAT)\d+|(?<=Number of solutions\t\t\t)[.e+\-\d]+)" || true)
        model_count="${model_count:-NA}"
        echo $dimacs,$solver,$analysis$suffix,$(echo "($end - $start) * 1000000000 / 1" | bc),$satisfiable,$model_count >> $res
    else
        echo "WARNING: No solver output for $dimacs with solver $solver and analysis $analysis" | tee -a $err
        echo $dimacs,$solver,$analysis$suffix,NA,NA,NA >> $res
    fi
)

run-void-analysis() (
    cat $dimacs_path | grep -E "^[^c]" > input.dimacs
    echo "  Void feature model / feature model cardinality"
    suffix=""
    run-solver
)

run-core-dead-analysis() (
    features=$(cat $base.features)
    i=1
    for f in $features; do
        fnum=$(cat $dimacs_path | grep " $f$" | cut -d' ' -f2 | head -n1)
        cat $dimacs_path | grep -E "^[^c]" > input.dimacs
        clauses=$(cat input.dimacs | grep -E ^p | cut -d' ' -f4)
        clauses=$((clauses + 1))
        sed -i "s/^\(p cnf [[:digit:]]\+ \)[[:digit:]]\+/\1$clauses/" input.dimacs
        echo "$2$fnum 0" >> input.dimacs
        echo "  $1 $f"
        suffix="$i-$f"
        run-solver
        i=$(($i+1))
    done
)

run-dead-analysis() (
    run-core-dead-analysis "Dead feature / feature cardinality" ""
)

run-core-analysis() (
    run-core-dead-analysis "Core feature" "-"
)

echo system,iteration,source,transformation,solver,analysis,solve_time,satisfiable,model_count >> $res
touch $err

rm -rf data/dimacs/*.features
for dimacs_path in data/dimacs/*.dimacs; do
    dimacs=$(basename $dimacs_path .dimacs | sed 's/,/_/')
    base_it=$(echo $dimacs_path | rev | cut -d, -f2- | rev)
    base=$(echo $base_it | sed 's/\(,.*,\).*,/\1/g')
    echo "Reading features for $dimacs"
    if [ ! -f $base.features ]; then
        touch $base.features
        features=$(cat $base_it,z3.dimacs | grep -E "^c [1-9]" | grep -v 'k!' | cut -d' ' -f3 | shuf --random-source=<(yes $RANDOM_SEED))
        i=1
        found=0
        while [ $found -lt $NUM_FEATURES ] && [ $i -le $(echo "$features" | wc -l) ]; do
            feature=$(echo "$features" | tail -n+$i | head -1)
            if ([ ! -f $base_it,featureide.dimacs ] || (cat $base_it,featureide.dimacs | grep -q " $feature$")) &&
               ([ ! -f $base_it,kconfigreader.dimacs ] || (cat $base_it,kconfigreader.dimacs | grep -q " $feature$")) &&
               ([ ! -f $base_it,z3.dimacs ] || (cat $base_it,z3.dimacs | grep -q " $feature$")); then
                echo $feature >> $base.features
                found=$(($found+1))
            else
                echo "WARNING: Feature $feature not found in all DIMACS files for $base_it" | tee -a $err
            fi
            i=$(($i+1))
        done
    fi
done
for dimacs_path in data/dimacs/*.dimacs; do
    dimacs=$(basename $dimacs_path .dimacs | sed 's/,/_/')
    base=$(echo $dimacs_path | rev | cut -d, -f2- | rev | sed 's/\(,.*,\).*,/\1/g')
    echo "Solving $dimacs"
    for solver in $SOLVERS; do
        for analysis in $ANALYSES; do
            if [[ $solver != sharpsat-* ]] || [[ $analysis != core ]]; then
                run-$analysis-analysis
            fi
        done
    done
done