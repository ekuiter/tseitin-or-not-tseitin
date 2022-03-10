#!/bin/bash

mkdir -p dimacs

for file in *.smt; do
    echo "Transforming $file"
    dimacs=dimacs/$(basename $file .smt).dimacs
    start=`date +%s.%N`
    python3 smt2dimacs.py $file > $dimacs
    end=`date +%s.%N`
    echo "c time $(echo "($end - $start) * 1000000000 / 1" | bc)" >> $dimacs
done