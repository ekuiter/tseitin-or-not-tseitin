# Comparing CNF Transformations for Feature-Model Analysis

## Replication Package

### Getting Started

First, install Docker. On Arch Linux, run:

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

After stage one is finished, DIMACS files will be written to the `dimacs_files` directory, named after the following scheme:

```
[project],[version],[iteration],[source: kconfigreader|kclause|hierarchy],[transformation: kconfigreader|kclause|featureide|z3].dimacs
```

### Debugging

To access the evaluation's Docker container while it is running (e.g., to `tail -f` the log file), run (where `$reader = kconfigreader|kclause`):

```
docker exec -it $(docker ps --filter name=$reader --format "{{.ID}}") /bin/bash
```

To start an interactive session in a (not already running) Docker container:

```
docker run -it $reader /bin/bash
```