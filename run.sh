#!/bin/bash
set -e
shopt -s extglob # needed for @(...|...) syntax below
READERS=(kconfigreader kclause) # Docker containers to use

# stage 1: call kconfigreader (extraction phase) and kclause
# stage 2: call Z3 and FeatureIDE
# stage 3: call kconfigreader (transformation phase)
# stage 4: call (#)SAT solvers

# stage 1: extract feature models (DIMACS files for kconfigreader),
# using recent versions of well-known Kconfig projects
if [[ ! -d dimacs ]] || [[ ! -d models ]]; then
    # clean up previous (incomplete) files
    rm -rf dimacs models kconfig_extractors/data_*
    mkdir -p dimacs models

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
                cp kconfig_extractors/data_$reader/models/$system/$file dimacs/$system,$newfile
            done
        done
    done

    # clean up failures and unneeded files
    rm -f dimacs/freetz-ng*kconfigreader.dimacs # fails due to memory overflow

    # move models for further processing
    mv dimacs/*.model models/
fi

# stage 2: extract DIMACS files with FeatureIDE and Z3
rm -rf spldev/data spldev/models* # todo: rename spldev (use stages?)
ls models > spldev/models.txt
mkdir -p spldev/models/
cp models/* spldev/models/
# todo: read kclause models correctly
docker build -f spldev/Dockerfile -t spldev spldev
docker rm -f spldev || true
docker run -m 16g -it --name spldev spldev evaluation-cnf/extract_cnf.sh
docker cp spldev:/home/spldev/evaluation-cnf/output spldev/data
docker rm -f spldev
# todo: copy dimacs files into right folder with right name and append number of new variables and literals

# todo: cdl/knueppel benchmark

# todo: export kclause/xml to formula to kconfigreader.model

# todo: call kconfigreader (transformation phase) on these files

# todo: solver stage