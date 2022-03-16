#!/bin/bash
set -e
shopt -s extglob # needed for @(...|...) syntax below
READERS=(kconfigreader kclause) # Docker containers with Kconfig extractors
ANALYSES=(void dead core) # analyses to run on feature models, see run-...-analysis functions below
ANALYSES=(void)
export N=3 # number of iterations
export TIMEOUT_TRANSFORM=300 # transformation timeout in seconds, should be consistent with stage2/evaluation-cnf/config/config.properties
export TIMEOUT_ANALYZE=60 # analysis timeout in seconds
export RANDOM_SEED=1503221735 # seed for choosing core/dead features
export NUM_FEATURES=5 # number of randomly chosen core/dead features

# evaluated systems and versions, should be consistent with stage13/extract_cnf.sh
SYSTEMS=(linux,v4.18 axtls,release-2.0.0 buildroot,2021.11.2 busybox,1_35_0 embtoolkit,embtoolkit-1.8.0 fiasco,58aa50a8aae2e9396f1c8d1d0aa53f2da20262ed freetz-ng,5c5a4d1d87ab8c9c6f121a13a8fc4f44c79700af toybox,0.8.6 uclibc-ng,v1.0.40 automotive,2_1 automotive,2_2 automotive,2_3 automotive,2_4 axtls,unknown busybox,1.18.0 ea2468,unknown embtoolkit,unknown linux,2.6.33.3 uclibc,unknown uclinux-base,unknown uclinux-distribution,unknown)

# evaluated (#)SAT solvers
# due to license issues, we do not upload solver binaries. all binaries were compiled/downloaded from http://www.satcompetition.org, https://github.com/sat-heritage/docker-images, or the download page of the respective solver
# we choose all winning SAT solvers in SAT competitions and well-known solvers in the SPL community
# for #SAT, we choose the eight fastest solvers as evaluated by Sundermann et al. 2021, found here: https://github.com/SoftVarE-Group/emse21-evaluation-sharpsat/tree/main/solvers
SOLVERS=(sat02-zchaff sat03-Forklift sat04-zchaff sat05-SatELiteGTI.sh sat06-MiniSat sat07-RSat.sh sat09-precosat sat10-CryptoMiniSat sat11-glucose.sh sat12-glucose.sh sat13-lingeling-aqw sat14-lingeling-ayv sat16-MapleCOMSPS_DRUP sat17-Maple_LCM_Dist sat18-MapleLCMDistChronoBT sat19-MapleLCMDiscChronoBT-DL-v3 sat20-Kissat-sc2020-sat sat21-Kissat_MAB sat-sat4j.sh sharpsat-c2d.sh sharpsat-countAntom sharpsat-d4 sharpsat-dsharp sharpsat-ganak sharpsat-miniC2D.sh sharpsat-sharpSAT)

# stage 1: extract feature models as .model files with kconfigreader-extract and kclause
if [[ ! -d _models ]]; then
    # clean up previous (incomplete) files
    rm -rf stage13/data_*
    mkdir -p _models

    # extract feature models with kconfigreader and kclause
    for reader in ${READERS[@]}; do
        # build Docker image
        docker build -f stage13/$reader/Dockerfile -t $reader stage13

        # run evaluation script inside Docker container
        # for other evaluations, you can run other scripts (e.g., extract_all.sh)
        docker rm -f $reader || true
        docker run -m 16g -e N -it --name $reader $reader ./extract_cnf.sh

        # copy evaluation results from Docker into host machine
        docker cp $reader:/home/data stage13/data_$reader

        # remove Docker container
        docker rm -f $reader
        
        # arrange files for further processing
        for system in stage13/data_$reader/models/*; do
            system=$(basename $system)
            for file in stage13/data_$reader/models/$system/*.model; do
                cp stage13/data_$reader/models/$system/$(basename $file) _models/$system,$(basename $file)
            done
        done
    done

    # add hierarchical models from Knüppel's "Is there a mismatch paper"
    rm -f _models/*.xml
    i=0
    while [ $i -ne $N ]; do
        i=$(($i+1))
        for m in hierarchies/*.xml; do
            cp $m _models/$(basename $m .xml),$i,hierarchy.xml
        done
    done
else
    echo Skipping stage 1
fi

# stage 2: transform .model files into .dimacs (FeatureIDE), .smt (z3), and .model (kconfigreader-transform)
if [[ ! -d _intermediate ]] || [[ ! -d _dimacs ]]; then
    rm -rf stage2/data stage2/models*
    mkdir -p _intermediate _dimacs
    ls _models > stage2/models.txt
    mkdir -p stage2/models/
    cp _models/* stage2/models/

    # build and run Docker image (analogous to above)
    docker build -f stage2/Dockerfile -t stage2 stage2
    docker rm -f stage2 || true
    docker run -m 16g -it --name stage2 stage2 evaluation-cnf/transform_cnf.sh
    docker cp stage2:/home/spldev/evaluation-cnf/output stage2/data
    docker rm -f stage2

    # arrange files for further processing
    for file in stage2/data/*/temp/*.@(dimacs|smt|model|stats); do
        newfile=$(basename $file | sed 's/\.model_/,/g' | sed 's/_0\././g' | sed 's/hierarchy_/hierarchy,/g')
        if [[ $newfile != *.stats ]] || [[ $newfile == *hierarchy* ]]; then
            cp $file _intermediate/$newfile
        fi
    done
    mv _intermediate/*.dimacs _dimacs || true
else
    echo Skipping stage 2
fi

# stage 3: transform .smt and .model files into .dimacs with z3 and kconfigreader-transform
if ! ls _dimacs | grep -q z3; then
    for reader in ${READERS[@]}; do
        rm -rf stage13/$reader/transform
        mkdir -p stage13/$reader/transform/
        cp _intermediate/*.@(smt|model) stage13/$reader/transform/
        docker build -f stage13/$reader/Dockerfile -t $reader stage13
        docker rm -f $reader || true
        docker run -m 16g -e TIMEOUT_TRANSFORM -it --name $reader $reader ./transform_cnf.sh
        docker cp $reader:/home/dimacs stage13/data_$reader
        docker rm -f $reader
        cp stage13/data_$reader/dimacs/* _dimacs/ || true
    done
else
    echo Skipping stage 3
fi

# stage 4: collect statistics in CSV file
res=_results_transform.csv
err=_error_transform.log
res_miss=_results_missing.csv
if [ ! -f $res ]; then
    rm -f $res $err $res_miss
    echo system,iteration,source,extract_time,extract_variables,extract_literals,transformation,transform_time,transform_variables,transform_literals >> $res
    touch $err $res_miss

    for system in ${SYSTEMS[@]}; do
        system_tag=$(echo $system | tr , _)
        model_num=$(ls _models/$system* 2>/dev/null | wc -l)
        if ! ([ $model_num -eq $(( 2*$N )) ] || ([ $model_num -eq $N ] && (ls _models/$system* | grep -q hierarchy))); then
            echo "WARNING: Missing feature models for $system" | tee -a $err
        else
            i=0
            while [ $i -ne $N ]; do
                i=$(($i+1))
                for source in kconfigreader kclause hierarchy; do
                    if [ -f _models/$system,$i,$source* ]; then
                        model=_models/$system,$i,$source.model
                        stats=_intermediate/$system,$i,hierarchy.stats
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
                            if [ -f _dimacs/$system,$i,$source,$transformation* ]; then
                                dimacs=_dimacs/$system,$i,$source,$transformation.dimacs
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
                                        echo $system_tag,$i,$source,$transformation,$solver,$analysis,NA >> $res_miss
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
    echo Skipping stage 4
fi

# stage 5: analyze transformed feature models with (#)SAT solvers
res=_results_analyze.csv
err=_error_analyze.log
run-solver() (
    log=../data/$dimacs,$solver,$analysis.log
    echo "    Running solver $solver for analysis $analysis"
    start=`date +%s.%N`
    (timeout $TIMEOUT_ANALYZE ./$solver input.dimacs > $log) || true
    end=`date +%s.%N`
    if cat $log | grep -q "SATISFIABLE" || cat $log | grep -q "^s " || cat $log | grep -q "# of solutions" || cat $log | grep -q "# solutions" || cat $log | grep -q " models"; then
        echo $dimacs,$solver,$analysis,$(echo "($end - $start) * 1000000000 / 1" | bc) >> ../../$res
    else
        echo "WARNING: No solver output for $dimacs with solver $solver and analysis $analysis" | tee -a ../../$err
        echo $dimacs,$solver,$analysis,NA >> ../../$res
fi
)
run-void-analysis() (
    cat $dimacs_path | grep -E "^[^c]" > input.dimacs
    echo "  Void feature model"
    run-solver
)
run-core-dead-analysis() (
    features=$(cat $dimacs_path | grep -E "^c [1-9]" | cut -d' ' -f2 | shuf --random-source=<(yes $RANDOM_SEED) | head -n$NUM_FEATURES)
    for f in $features; do
        echo "  $1 feature $f"
        cat $dimacs_path | grep -E "^[^c]" > input.dimacs
        clauses=$(cat input.dimacs | grep -E ^p | cut -d' ' -f4)
        clauses=$((clauses + 1))
        sed -i "s/^\(p cnf [[:digit:]]\+ \)[[:digit:]]\+/\1$clauses/" input.dimacs
        echo "$2$f 0" >> input.dimacs
        run-solver
    done
)
run-dead-analysis() (
    run-core-dead-analysis "Dead" ""
)
run-core-analysis() (
    run-core-dead-analysis "Core" "-"
)
if [ ! -f $res ]; then
    rm -rf stage5/data $res $err
    echo system,iteration,source,transformation,solver,analysis,solve_time >> $res
    touch $err
    mkdir -p stage5/data
    cd stage5/bin
    for dimacs_path in ../../_dimacs/*.dimacs; do
        dimacs=$(basename $dimacs_path .dimacs | sed 's/,/_/')
        echo "Processing $dimacs"
        for solver in ${SOLVERS[@]}; do
            for analysis in ${ANALYSES[@]}; do
                run-$analysis-analysis
            done
        done
    done
    cd ../..
    cat $res_miss >> $res
else
    echo Skipping stage 5
fi

echo
cat _error*
