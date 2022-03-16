#!/bin/bash
set -e
CONTAINERS=(kconfigreader kclause stage2)

for container in ${CONTAINERS[@]}; do
    docker load -i $container.tar.gz
done