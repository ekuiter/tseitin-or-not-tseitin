## Comparing CNF Transformations for Feature-Model Analysis

### Replication Package

#### Getting Started

First, [install Docker](https://docs.docker.com/get-docker/) on a Linux system (or virtual machine). On Arch Linux, for example, run:

```
usermod -aG docker $(whoami) # then, log out and in again
sudo pacman -S docker
systemctl enable docker
systemctl start docker
```

Then, run the evaluation with `./run.sh`.
To re-run the evaluation, run `rm -rf _* && ./run.sh`.
You can control which stages to (re-)run by prepolutating/removing files in the `_models`, `_transform`, and `_dimacs` directories.
For an overview over the individual stages, see the source code of `run.sh`.

The transformed DIMACS files are stored in the `_dimacs` directory, named after the following scheme:

```
[project],[version],[iteration],[source],[transformation].dimacs
```

The time measurements are stored in `_results.csv`.

#### Im-/Export

To im-/export preconfigured Docker containers (download available [here](todo)), run `./import.sh` and `./export.sh`, respectively.
(This ensures the reproduceability of our results even when the Docker files fail to build from scratch.)

#### Debugging

To access the evaluation's Docker container while it is running (e.g., to `tail -f` the log file), run (where `$reader = kconfigreader|kclause`):

```
docker exec -it $(docker ps --filter name=$reader --format "{{.ID}}") /bin/bash
```

To start an interactive session in a (not already running) Docker container:

```
docker run -it $reader /bin/bash
```