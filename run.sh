#!/bin/bash
set -e
shopt -s extglob # needed for @(...|...) syntax below
READERS=(kconfigreader kclause) # Docker containers with Kconfig extractors
export N=1 # number of iterations

# evaluated systems and versions, should be consistent with stage13/extract_cnf.sh
SYSTEMS=(linux,v4.18 axtls,release-2.0.0 buildroot,2021.11.2 busybox,1_35_0 embtoolkit,embtoolkit-1.8.0 fiasco,58aa50a8aae2e9396f1c8d1d0aa53f2da20262ed freetz-ng,5c5a4d1d87ab8c9c6f121a13a8fc4f44c79700af toybox,0.8.6 uclibc-ng,v1.0.40 automotive,2_1 automotive,2_2 automotive,2_3 automotive,2_4 axtls,unknown busybox,1.18.0 ea2468,unknown embtoolkit,unknown linux,2.6.33.3 uclibc,unknown uclinux-base,unknown uclinux-distribution,unknown)
SYSTEMS=(axtls,release-2.0.0)

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
            echo #cp $m _models/$(basename $m .xml),$i,hierarchy.xml
        done
    done
else
    echo Skipping stage 1
fi

# stage 2: transform .model files into .dimacs (FeatureIDE), .smt (z3), and .model (kconfigreader-transform)
if [[ ! -d _transform ]] || [[ ! -d _dimacs ]]; then
    rm -rf stage2/data stage2/models*
    mkdir -p _transform _dimacs
    ls _models > stage2/models.txt
    mkdir -p stage2/models/
    cp _models/* stage2/models/

    # build and run Docker image (analogous to above)
    docker build -f stage2/Dockerfile -t stage2 stage2
    docker rm -f stage2 || true
    # todo: FeatureIDE 3.8.0 or 3.5.5?
    docker run -m 16g -it --name stage2 stage2 evaluation-cnf/transform_cnf.sh
    docker cp stage2:/home/spldev/evaluation-cnf/output stage2/data
    docker rm -f stage2

    # arrange files for further processing
    for file in stage2/data/*/temp/*.@(dimacs|smt|model); do
        newfile=$(basename $file | sed 's/\.model\(.\)/\1/g' | sed 's/_0//g' | tr _ ,)
        cp $file _transform/$newfile
    done
    mv _transform/*.dimacs _dimacs
else
    echo Skipping stage 2
fi

# stage 3: transform .smt and .model files into .dimacs with z3 and kconfigreader-transform
if ! ls _dimacs | grep -q z3; then
    for reader in ${READERS[@]}; do
        rm -rf stage13/$reader/transform
        mkdir -p stage13/$reader/transform/
        cp _transform/* stage13/$reader/transform/
        docker build -f stage13/$reader/Dockerfile -t $reader stage13
        docker rm -f $reader || true
        docker run -m 16g -it --name $reader $reader ./transform_cnf.sh
        docker cp $reader:/home/dimacs stage13/data_$reader
        docker rm -f $reader
        cp stage13/data_$reader/dimacs/* _dimacs/
    done
else
    echo Skipping stage 3
fi

# stage 4: call (#)SAT solvers

# todo: solver stage

# stage 5: collect statistics in CSV file
res=_results.csv
if [ ! -f $res ]; then
    echo system,iteration,source,extract_time,extract_variables,extract_literals,transformation,transform_time,transform_variables,transform_literals >> $res

    for system in ${SYSTEMS[@]}; do
        system_tag=$(echo $system | tr , _)
        model_num=$(ls _models/$system* 2>/dev/null | wc -l)
        if ! ([ $model_num -eq $(( 2*$N )) ] || ([ $model_num -eq $N ] && (ls _models/$system* | grep -q hierarchy))); then
            echo "WARNING: Missing feature models for $system"
        else
            i=0
            while [ $i -ne $N ]; do
                i=$(($i+1))
                for source in kconfigreader kclause hierarchy; do
                    if [ -f _models/$system,$i,$source* ]; then
                        model=_models/$system,$i,$source.model
                        echo Processing $model
                        extract_time=$(cat $model | grep "#item time" | cut -d' ' -f3)
                        extract_variables=$(cat $model | sed "s/)/)\n/g" | grep "def(" | sed "s/.*def(\(.*\)).*/\1/g" | sort | uniq | wc -l)
                        extract_literals=$(cat $model | sed "s/)/)\n/g" | grep "def(" | wc -l)
                        for transformation in featureide z3 kconfigreader; do
                            if [ -f _dimacs/$system,$i,$source,$transformation* ]; then
                                dimacs=_dimacs/$system,$i,$source,$transformation.dimacs
                                echo Processing $dimacs
                                transform_time=$(cat $dimacs | grep "c time" | cut -d' ' -f3)
                                transform_variables=$(cat $dimacs | grep -E ^p | cut -d' ' -f3)
                                transform_literals=$(cat $dimacs | grep -E "^[^pc]" | grep -Fo ' ' | wc -l)
                                echo $system_tag,$i,$source,$extract_time,$extract_variables,$extract_literals,$transformation,$transform_time,$transform_variables,$transform_literals >> $res
                            else
                                echo "WARNING: Missing DIMACS file for $system with source $source and transformation $transformation"
                                echo $system_tag,$i,$source,$extract_time,$extract_variables,$extract_literals,$transformation,NA,NA,NA >> $res
                            fi
                        done
                    fi
                done
            done
        fi
    done
else
    echo Skipping stage 5
fi

echo
echo Evaluation results
echo ==================
echo
cat $res