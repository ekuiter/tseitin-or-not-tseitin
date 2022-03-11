#!/bin/bash
set -e
shopt -s extglob # needed for @(...|...) syntax below
READERS=(kconfigreader kclause) # Docker containers to use
N=1 # number of iterations

# stage 1: call kconfigreader (extraction phase) and kclause
# stage 2: call Z3 and FeatureIDE
# stage 3: call kconfigreader (transformation phase)
# stage 4: call (#)SAT solvers

# stage 1: extract feature models (DIMACS files for kconfigreader),
# using recent versions of well-known Kconfig projects
if [[ ! -d _dimacs ]] || [[ ! -d _models ]]; then
    # clean up previous (incomplete) files
    rm -rf _dimacs _models kconfig_extractors/data_*
    mkdir -p _dimacs _models

    # extract feature models with kconfigreader and kclause
    for reader in ${READERS[@]}; do
        # build Docker image
        docker build -f kconfig_extractors/$reader/Dockerfile -t $reader kconfig_extractors

        # run evaluation script inside Docker container
        # for other evaluations, you can run other scripts (e.g., extract_all.sh)
        docker rm -f $reader || true
        docker run -m 16g -it --name $reader $reader ./extract_cnf.sh

        # copy evaluation results from Docker into main machine
        docker cp $reader:/home/data kconfig_extractors/data_$reader

        # remove Docker container
        docker rm -f $reader
        
        # arrange files for further processing
        for system in kconfig_extractors/data_$reader/models/*; do
            system=$(basename $system)
            for file in kconfig_extractors/data_$reader/models/$system/*.@(dimacs|model); do
                file=$(basename $file)
                if [[ $file == *".dimacs" ]]; then
                    newfile=${file/$reader/$reader,$reader}
                else
                    newfile=$file
                fi
                cp kconfig_extractors/data_$reader/models/$system/$file _dimacs/$system,$newfile
            done
        done
    done

    # clean up failures and unneeded files
    rm -f _dimacs/freetz-ng*kconfigreader.dimacs # fails due to memory overflow

    # move models for further processing
    mv _dimacs/*.model _models/

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

# stage 2: extract DIMACS and SMT files with FeatureIDE and Z3
if [[ ! -d _smt ]]; then
    rm -rf spldev/data spldev/models* # todo: rename spldev (use stages?)
    ls _models > spldev/models.txt
    mkdir -p spldev/models/
    cp _models/* spldev/models/

    # build and run Docker image, similar as above
    docker build -f spldev/Dockerfile -t spldev spldev
    docker rm -f spldev || true
    docker run -m 16g -it --name spldev spldev evaluation-cnf/extract_cnf.sh
    docker cp spldev:/home/spldev/evaluation-cnf/output spldev/data
    docker rm -f spldev

    # arrange files for further processing
    for file in spldev/data/*/temp/*.@(dimacs|smt); do
        newfile=$(basename $file | sed 's/\.model//g' | sed 's/_0//g' | tr _ ,)
        cp $file _dimacs/$newfile
    done
    mkdir -p _transform
    mv _dimacs/*.smt _transform
fi

# stage 3:
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

# todo: export kclause/xml to formula to kconfigreader.model

# todo: call kconfigreader (transformation phase) on these files

# todo: solver stage