#!/bin/bash
set -ea
shopt -s extglob # needed for @(...|...) syntax below
source params.ini
mkdir -p data

# stage 1: extract feature models as .model files with kconfigreader-extract and kclause
if [[ ! -d data/models ]]; then
    # clean up previous (incomplete) files
    rm -rf data/kconfigreader data/kclause
    mkdir -p data/models

    # extract feature models with kconfigreader and kclause
    for reader in ${READERS[@]}; do
        # build Docker image
        if [[ $SKIP_BUILD != y ]]; then
            docker build -f stage1/$reader/Dockerfile -t stage1_$reader stage1
        fi

        # run evaluation script inside Docker container
        # for other evaluations, you can run other scripts (e.g., extract_all.sh)
        docker run --rm -m 16g -e KCONFIG -e N -v $PWD/data/stage1_${reader}_output:/home/data stage1_$reader ./extract_cnf.sh
        
        # arrange files for further processing
        for system in data/stage1_${reader}_output/models/*; do
            system=$(basename $system)
            for file in data/stage1_${reader}_output/models/$system/*.model; do
                cp data/stage1_${reader}_output/models/$system/$(basename $file) data/models/$system,$(basename $file)
            done
        done
    done

    # add hierarchical models from Knüppel's "Is there a mismatch paper"
    rm -f data/models/*.xml
    i=0
    while [ $i -ne $N ]; do
        i=$(($i+1))
        for h in ${HIERARCHIES[@]}; do
            cp hierarchies/$h.xml data/models/$(basename $h .xml),$i,hierarchy.xml
        done
    done
else
    echo Skipping stage 1
fi

# stage 2a: transform .model files into .dimacs (FeatureIDE), .smt (z3), and .model (kconfigreader-transform)
if [[ ! -d data/intermediate ]] || [[ ! -d data/dimacs ]]; then
    rm -rf data/stage2_output
    mkdir -p data/stage2_output data/intermediate data/dimacs
    ls data/models > data/stage2_output/models.txt
    cp -r data/models data/stage2_output/models

    # build and run Docker image (analogous to above)
    if [[ $SKIP_BUILD != y ]]; then
        docker build -f stage2/Dockerfile -t stage2 stage2
    fi
    docker run --rm -m 16g -e TIMEOUT_TRANSFORM -v $PWD/data/stage2_output:/home/spldev/evaluation-cnf/output stage2 evaluation-cnf/transform_cnf.sh

    # arrange files for further processing
    for file in data/stage2_output/*/temp/*.@(dimacs|smt|model|stats); do
        newfile=$(basename $file | sed 's/\.model_/,/g' | sed 's/_0\././g' | sed 's/hierarchy_/hierarchy,/g')
        if [[ $newfile != *.stats ]] || [[ $newfile == *hierarchy* ]]; then
            cp $file data/intermediate/$newfile
        fi
    done
    mv data/intermediate/*.dimacs data/dimacs || true
else
    echo Skipping stage 2a
fi

# stage 2b: transform .smt and .model files into .dimacs with z3 and kconfigreader-transform
if ! ls data/dimacs | grep -q z3; then
    for reader in ${READERS[@]}; do
        rm -rf data/stage2_${reader}_output
        mkdir -p data/stage2_${reader}_output
        cp data/intermediate/*.@(smt|model) data/stage2_${reader}_output
        if [[ $SKIP_BUILD != y ]]; then
            docker build -f stage1/$reader/Dockerfile -t stage1_$reader stage1
        fi
        docker run --rm -m 16g -e TIMEOUT_TRANSFORM -v $PWD/data/stage2_${reader}_output:/home/data stage1_$reader ./transform_cnf.sh
        cp data/stage2_${reader}_output/*.dimacs data/dimacs || true
    done
else
    echo Skipping stage 2b
fi

# stage 2c: collect statistics in CSV file
res=data/results_transform.csv
err=data/error_transform.log
res_miss=data/results_missing.csv
if [ ! -f $res ]; then
    rm -f $res $err $res_miss
    echo system,iteration,source,extract_time,extract_variables,extract_literals,transformation,transform_time,transform_variables,transform_literals >> $res
    touch $err $res_miss

    SYSTEMS=("${KCONFIG[@]}" "${HIERARCHIES[@]}")
    for system in ${SYSTEMS[@]}; do
        system_tag=$(echo $system | tr , _)
        model_num=$(ls data/models/$system* 2>/dev/null | wc -l)
        if ! ([ $model_num -eq $(( 2*$N )) ] || ([ $model_num -eq $N ] && (ls data/models/$system* | grep -q hierarchy))); then
            echo "WARNING: Missing feature models for $system" | tee -a $err
        else
            i=0
            while [ $i -ne $N ]; do
                i=$(($i+1))
                for source in kconfigreader kclause hierarchy; do
                    if [ -f data/models/$system,$i,$source* ]; then
                        model=data/models/$system,$i,$source.model
                        stats=data/intermediate/$system,$i,hierarchy.stats
                        echo "Processing $model"
                        if [ -f $model ]; then
                            extract_time=$(cat $model | grep "#item time" | cut -d' ' -f3)
                            extract_variables=$(cat $model | sed "s/)/)\n/g" | grep "def(" | sed "s/.*def(\(.*\)).*/\1/g" | sort | uniq | wc -l)
                            extract_literals=$(cat $model | sed "s/)/)\n/g" | grep "def(" | wc -l)
                        else
                            extract_time=NA
                            extract_variables=$(cat $stats | cut -d' ' -f1)
                            extract_literals=$(cat $stats | cut -d' ' -f2)
                        fi
                        for transformation in featureide z3 kconfigreader; do
                            if [ -f data/dimacs/$system,$i,$source,$transformation* ]; then
                                dimacs=data/dimacs/$system,$i,$source,$transformation.dimacs
                                echo Processing $dimacs
                                transform_time=$(cat $dimacs | grep "c time" | cut -d' ' -f3)
                                transform_variables=$(cat $dimacs | grep -E ^p | cut -d' ' -f3)
                                transform_literals=$(cat $dimacs | grep -E "^[^pc]" | grep -Fo ' ' | wc -l)
                                echo $system_tag,$i,$source,$extract_time,$extract_variables,$extract_literals,$transformation,$transform_time,$transform_variables,$transform_literals >> $res
                            else
                                echo "WARNING: Missing DIMACS file for $system with source $source and transformation $transformation" | tee -a $err
                                echo $system_tag,$i,$source,$extract_time,$extract_variables,$extract_literals,$transformation,NA,NA,NA >> $res
                                for solver in ${SOLVERS[@]}; do
                                    for analysis in ${ANALYSES[@]}; do
                                        if [[ $solver != sharpsat-* ]] || [[ $analysis != core ]]; then
                                            if [[ $analysis == void ]]; then
                                                echo $system_tag,$i,$source,$transformation,$solver,$analysis,NA,NA,NA >> $res_miss
                                            else
                                                j=0
                                                while [ $j -ne $NUM_FEATURES ]; do
                                                    j=$(($j+1))
                                                    echo $system_tag,$i,$source,$transformation,$solver,$analysis$j,NA,NA,NA >> $res_miss
                                                done
                                            fi
                                        fi
                                    done
                                done
                            fi
                        done
                    fi
                done
            done
        fi
    done
else
    echo Skipping stage 2c
fi

# stage 3: analyze transformed feature models with (#)SAT solvers
res=data/results_analyze.csv
err=data/error_analyze.log
if [ ! -f $res ] && [[ $SKIP_ANALYSIS != y ]]; then
    rm -rf data/stage3_output $res $err
    mkdir -p data/stage3_output
    cp -r data/dimacs data/stage3_output/dimacs
    if [[ $SKIP_BUILD != y ]]; then
        docker build -f stage3/Dockerfile -t stage3 stage3
    fi
    docker run --rm -m 16g -e ANALYSES -e TIMEOUT_ANALYZE -e RANDOM_SEED -e NUM_FEATURES -e SOLVERS -v $PWD/data/stage3_output:/home/data stage3 ./solve_cnf.sh
    cp data/stage3_output/results_analyze.csv $res
    cp data/stage3_output/error_analyze.log $err
    cat $res_miss >> $res
else
    echo Skipping stage 3
fi

cp params.ini data/params.ini
echo
cat data/error*
