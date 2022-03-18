#!/bin/bash
set -e
CONTAINERS=(kconfigreader kclause stage2)

docker build -f stage13/kconfigreader/Dockerfile -t kconfigreader stage13
docker build -f stage13/kclause/Dockerfile -t kclause stage13
docker build -f stage2/Dockerfile -t stage2 stage2

for container in ${CONTAINERS[@]}; do
    docker save $container | gzip > $container.tar.gz
done