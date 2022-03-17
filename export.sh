#!/bin/bash
set -e
CONTAINERS=(kconfigreader kclause stage2)

for container in ${CONTAINERS[@]}; do
    docker save $container | gzip > $container.tar.gz
done