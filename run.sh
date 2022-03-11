#!/bin/bash
set -e
shopt -s extglob # needed for @(...|...) syntax below
READERS=(kconfigreader kclause) # Docker containers with Kconfig extractors
N=1 # number of iterations

# stage 1: extract feature models as .model files with kconfigreader-extract and kclause
if [[ ! -d _models ]]; then
    # clean up previous (incomplete) files
    rm -rf kconfig_extractors/data_*
    mkdir -p _models

    # extract feature models with kconfigreader and kclause
    for reader in ${READERS[@]}; do
        # build Docker image
        docker build -f kconfig_extractors/$reader/Dockerfile -t $reader kconfig_extractors

        # run evaluation script inside Docker container
        # for other evaluations, you can run other scripts (e.g., extract_all.sh)
        docker rm -f $reader || true
        docker run -m 16g -it --name $reader $reader ./extract_cnf.sh

        # copy evaluation results from Docker into host machine
        docker cp $reader:/home/data kconfig_extractors/data_$reader

        # remove Docker container
        docker rm -f $reader
        
        # arrange files for further processing
        for system in kconfig_extractors/data_$reader/models/*; do
            system=$(basename $system)
            for file in kconfig_extractors/data_$reader/models/$system/*.model; do
                cp kconfig_extractors/data_$reader/models/$system/$(basename $file) _models/$system,$(basename $file)
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
    rm -rf spldev/data spldev/models* # todo: rename spldev (use stages?)
    mkdir -p _transform _dimacs
    ls _models > spldev/models.txt
    mkdir -p spldev/models/
    cp _models/* spldev/models/

    # build and run Docker image (analogous to above)
    docker build -f spldev/Dockerfile -t spldev spldev
    docker rm -f spldev || true
    docker run -m 16g -it --name spldev spldev evaluation-cnf/extract_cnf.sh
    docker cp spldev:/home/spldev/evaluation-cnf/output spldev/data
    docker rm -f spldev

    # arrange files for further processing
    for file in spldev/data/*/temp/*.@(dimacs|smt|model); do
        newfile=$(basename $file | sed 's/\.model\(.\)/\1/g' | sed 's/_0//g' | tr _ ,)
        cp $file _transform/$newfile
    done
    mv _transform/*.dimacs _dimacs
fi

# stage 3: transform .smt and .model files into .dimacs with z3 and kconfigreader-transform
if ! ls _dimacs | grep -q z3; then
    for reader in ${READERS[@]}; do
        rm -rf kconfig_extractors/$reader/transform
        mkdir -p kconfig_extractors/$reader/transform/
        cp _transform/* kconfig_extractors/$reader/transform/
        docker build -f kconfig_extractors/$reader/Dockerfile -t $reader kconfig_extractors
        docker rm -f $reader || true
        docker run -m 16g -it --name $reader $reader ./transform_cnf.sh
        docker cp $reader:/home/dimacs kconfig_extractors/data_$reader
        docker rm -f $reader
        cp kconfig_extractors/data_$reader/dimacs/* _dimacs/
    done
fi

# stage 4: call (#)SAT solvers

# todo: solver stage