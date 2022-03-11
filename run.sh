#!/bin/bash
set -e
shopt -s extglob # needed for @(...|...) syntax below
READERS=(kconfigreader kclause) # Docker containers with Kconfig extractors
N=1 # number of iterations

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
        docker run -m 16g -it --name $reader $reader ./extract_cnf.sh

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
    docker run -m 16g -it --name stage2 stage2 evaluation-cnf/extract_cnf.sh
    docker cp stage2:/home/spldev/evaluation-cnf/output stage2/data
    docker rm -f stage2

    # arrange files for further processing
    for file in stage2/data/*/temp/*.@(dimacs|smt|model); do
        newfile=$(basename $file | sed 's/\.model\(.\)/\1/g' | sed 's/_0//g' | tr _ ,)
        cp $file _transform/$newfile
    done
    mv _transform/*.dimacs _dimacs
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
fi

# stage 4: call (#)SAT solvers

# todo: solver stage