#!/bin/bash
rm -rf _* stage13/data_* stage13/*/transform stage2/data stage2/models* stage5/data
docker rm -f kconfigreader kclause stage2 || true