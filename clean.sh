#!/bin/bash
rm -rf data
docker rm -f kconfigreader kclause stage2 || true