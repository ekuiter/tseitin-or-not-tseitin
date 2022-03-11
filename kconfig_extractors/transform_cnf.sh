#!/bin/bash
shopt -s extglob

if [[ -d "kconfigreader" ]]; then
    READER=kconfigreader
elif [[ -d "kmax" ]]; then
    READER=kclause
else
    echo "no reader found, please run script inside of Docker"
    exit 1
fi

mkdir -p dimacs

for file in *.@(model|smt); do
    echo "Transforming $file"
    if [ $READER = kconfigreader ] && [[ $file == *.model ]]; then
        dimacs=dimacs/$(basename $file .model).dimacs
        start=`date +%s.%N`
        /home/kconfigreader/run.sh de.fosd.typechef.kconfig.TransformCNF $(basename $file .model)
        end=`date +%s.%N`
        mv $(basename $file .model).dimacs $dimacs
        echo "c time $(echo "($end - $start) * 1000000000 / 1" | bc)" >> $dimacs
    elif [ $READER = kclause ] && [[ $file == *.smt ]]; then
        dimacs=dimacs/$(basename $file .smt).dimacs
        start=`date +%s.%N`
        python3 smt2dimacs.py $file > $dimacs
        end=`date +%s.%N`
        echo "c time $(echo "($end - $start) * 1000000000 / 1" | bc)" >> $dimacs
    fi
done