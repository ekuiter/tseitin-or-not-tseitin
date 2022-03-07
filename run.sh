#!/bin/bash
set -e
shopt -s extglob # needed for @(...|...) syntax below
READERS=(kconfigreader kclause) # Docker containers to use

# stage one: extract feature models + DIMACS files from recent versions well-known Kconfig projects
if [[ ! -d dimacs ]] || [[ ! -d models ]]; then
    # clean up previous (incomplete) files
    rm -rf dimacs models kconfig_to_dimacs/data_*
    mkdir -p dimacs models

    # extract feature models + DIMACS files with kconfigreader and kclause
    for reader in ${READERS[@]}; do
        # build Docker image
        docker build -f kconfig_to_dimacs/$reader/Dockerfile -t $reader kconfig_to_dimacs

        # run evaluation script inside Docker container
        # for other evaluations, you can run other scripts (e.g., extract_all.sh)
        docker rm -f $reader || true
        docker run -m 16g -it --name $reader $reader ./extract_cnf.sh

        # copy evaluation results from Docker into main machine
        docker cp $reader:/home/data kconfig_to_dimacs/data_$reader

        # remove Docker container
        docker rm -f $reader
        
        # arrange DIMACS files for further processing
        for system in kconfig_to_dimacs/data_$reader/models/*; do
            system=$(basename $system)
            for file in kconfig_to_dimacs/data_$reader/models/$system/*.@(dimacs|model); do
                file=$(basename $file)
                if [[ $file == *".dimacs" ]]; then
                    newfile=${file/$reader/$reader,$reader}
                else
                    newfile=$file
                fi
                cp kconfig_to_dimacs/data_$reader/models/$system/$file dimacs/$system,$newfile
            done
        done
    done

    # clean up failures and unneeded files
    rm -f dimacs/freetz-ng*kconfigreader.dimacs # fails due to memory overflow
    rm -f dimacs/*kclause.model # not used in later stages

    # move kconfigreader models for further processing
    mv dimacs/*.model models/
fi

# stage two: ...

rm -rf spldev/data spldev/models*
ls models > spldev/models.txt
mkdir -p spldev/models/
cp models/* spldev/models/
docker build -f spldev/Dockerfile -t spldev spldev
docker rm -f spldev || true
docker run -m 16g -it --name spldev spldev evaluation-cnf/extract_cnf.sh
docker cp spldev:/home/spldev/evaluation-cnf/output spldev/data
docker rm -f spldev
#docker run -it --name $reader $reader ./extract_cnf.sh
