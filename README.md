## Comparing CNF Transformations for Feature-Model Analysis

### Replication Package

#### Getting Started

First, [install Docker](https://docs.docker.com/get-docker/) on a 64-bit Linux system. On Arch Linux, for example, run:

```
usermod -aG docker $(whoami) # then, log out and in again
sudo pacman -S docker
systemctl enable docker
systemctl start docker
```

Then, run the evaluation with `sudo ./run.sh` (`sudo` is recommended to avoid permission issues with files created by Docker).
To re-run the evaluation, run `sudo ./clean.sh && sudo ./run.sh`.
You can control which stages to (re-)run by prepolutating/removing files in the `data` directory.
For an overview over the individual stages, see the source code of `run.sh`.

The transformed DIMACS files are stored in the `data/dimacs` directory, named after the following scheme:

```
[project],[version],[iteration],[source],[transformation].dimacs
```

The time measurements are stored in `data/results_*.csv`, errors in `data/error_*.log`.

#### Im-/Export

To im-/export preconfigured Docker containers (download available [here](https://github.com/ekuiter/comparing-cnf-transformations/releases)), run `./import.sh` and `./export.sh`, respectively.
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