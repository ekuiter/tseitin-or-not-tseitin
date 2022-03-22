#!/bin/bash
set -e
shopt -s extglob # needed for @(...|...) syntax below
READERS=(kconfigreader kclause) # Docker containers with Kconfig extractors
export ANALYSES="void dead core" # analyses to run on feature models, see run-...-analysis functions below
export N=3 # number of iterations
export TIMEOUT_TRANSFORM=180 # transformation timeout in seconds, should be consistent with stage2/evaluation-cnf/config/config.properties
export TIMEOUT_ANALYZE=180 # analysis timeout in seconds
export RANDOM_SEED=2203212119 # seed for choosing core/dead features
export NUM_FEATURES=1 # number of randomly chosen core/dead features
SKIP_BUILD=y # whether to skip building Docker images, useful for using imported images

# evaluated systems and versions, should be consistent with stage1/extract_cnf.sh
SYSTEMS=(linux,v4.18 axtls,release-2.0.0 buildroot,2021.11.2 busybox,1_35_0 embtoolkit,embtoolkit-1.8.0 fiasco,58aa50a8aae2e9396f1c8d1d0aa53f2da20262ed freetz-ng,5c5a4d1d87ab8c9c6f121a13a8fc4f44c79700af toybox,0.8.6 uclibc-ng,v1.0.40 automotive,2_1 automotive,2_2 automotive,2_3 automotive,2_4 axtls,unknown busybox,1.18.0 ea2468,unknown embtoolkit,unknown linux,2.6.33.3 uclibc,unknown uclinux-base,unknown uclinux-distribution,unknown)

# evaluated (#)SAT solvers
# due to license issues, we do not upload solver binaries. all binaries were compiled/downloaded from http://www.satcompetition.org, https://github.com/sat-heritage/docker-images, or the download page of the respective solver
# we choose all winning SAT solvers in SAT competitions and well-known solvers in the SPL community
# for #SAT, we choose the five fastest solvers as evaluated by Sundermann et al. 2021, found here: https://github.com/SoftVarE-Group/emse21-evaluation-sharpsat/tree/main/solvers
export SOLVERS="sat02-zchaff sat03-Forklift sat04-zchaff sat05-SatELiteGTI.sh sat06-MiniSat sat07-RSat.sh sat09-precosat sat10-CryptoMiniSat sat11-glucose.sh sat12-glucose.sh sat13-lingeling-aqw sat14-lingeling-ayv sat16-MapleCOMSPS_DRUP sat17-Maple_LCM_Dist sat18-MapleLCMDistChronoBT sat19-MapleLCMDiscChronoBT-DL-v3 sat20-Kissat-sc2020-sat sat21-Kissat_MAB sharpsat-countAntom sharpsat-d4 sharpsat-dsharp sharpsat-ganak sharpsat-sharpSAT"

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
        docker run --rm -m 16g -e N -v $PWD/data/stage1_${reader}_output:/home/data stage1_$reader ./extract_cnf.sh
        
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
        for m in hierarchies/*.xml; do
            cp $m data/models/$(basename $m .xml),$i,hierarchy.xml
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
    docker run --rm -m 16g -v $PWD/data/stage2_output:/home/spldev/evaluation-cnf/output stage2 evaluation-cnf/transform_cnf.sh

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
        rm -rf data/stage3_${reader}_output
        mkdir -p data/stage3_${reader}_output
        cp data/intermediate/*.@(smt|model) data/stage3_${reader}_output
        if [[ $SKIP_BUILD != y ]]; then
            docker build -f stage1/$reader/Dockerfile -t stage1_$reader stage1
        fi
        docker run --rm -m 16g -e TIMEOUT_TRANSFORM -v $PWD/data/stage3_${reader}_output:/home/data stage1_$reader ./transform_cnf.sh
        cp data/stage3_${reader}_output/*.dimacs data/dimacs || true
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
                                        echo $system_tag,$i,$source,$transformation,$solver,$analysis,NA,NA >> $res_miss
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
if [ ! -f $res ]; then
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

echo
cat data/error*
