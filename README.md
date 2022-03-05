# Comparing CNF Transformations for Feature-Model Analysis

## Replication Package

First, install Docker. On Arch Linux:

```
usermod -aG docker $(whoami) # then, log out and in again
sudo pacman -S docker
systemctl enable docker
systemctl start docker
```

Then, run the evaluation:

```
./run.sh
```

When the evaluation is finished, results will be written to the `data` directory, named after the following scheme:

```
[project],[version],[iteration],[source: kconfigreader|kclause|benchmark],[transformation: kconfigreader|kclause|featureide|z3].dimacs
```

To access the evaluation's Docker container while it is running (e.g., to `tail -f` the log file), run (where TOOL = kconfigreader or kclause):

```
docker exec -it $(docker ps --filter name=TOOL --format "{{.ID}}") /bin/bash
```
