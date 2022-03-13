#!/bin/bash
set -e
CONTAINERS=(kconfigreader kclause stage2)

rm -rf _export
mkdir -p _export

for container in ${CONTAINERS[@]}; do
    docker save $container | gzip > _export/$container.tar.gz
done

cp import.sh _export/
cp -r _dimacs _export/dimacs
cp -r _models _export/models
cp -r _transform _export/transform
cp -r _results.csv _export/results.csv