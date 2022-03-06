#!/bin/bash
shopt -s extglob # needed for @(...|...) syntax below
READERS=(kconfigreader kclause) # Docker containers to use

# stage one: extract feature models + DIMACS files from recent versions well-known Kconfig projects
if [[ ! -d dimacs_files ]] || [[ ! -d model_files ]]; then
    # clean up previous (incomplete) files
    rm -rf dimacs_files model_files kconfig_to_dimacs/data_*
    mkdir dimacs_files model_files

    # extract feature models + DIMACS files with kconfigreader and kclause
    for reader in ${READERS[@]}; do
        # build Docker image
        docker build -f kconfig_to_dimacs/$reader/Dockerfile -t $reader kconfig_to_dimacs

        # run evaluation script inside Docker container
        # for other evaluations, you can run other scripts (e.g., extract_all.sh)
        docker run -it --name $reader $reader ./extract_cnf.sh

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
                cp kconfig_to_dimacs/data_$reader/models/$system/$file dimacs_files/$system,$newfile
            done
        done
    done

    # clean up failures and unneeded files
    rm -f dimacs_files/freetz-ng*kconfigreader.dimacs # fails due to memory overflow
    rm -f dimacs_files/*kclause.model # not used in later stages

    # move kconfigreader models for further processing
    mkdir model_files
    mv dimacs_files/*.model model_files/
fi