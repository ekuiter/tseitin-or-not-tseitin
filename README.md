## Comparing CNF Transformations for Feature-Model Analysis

This repository provides Docker automation for investigating transformations of feature-model formulas into conjunctive normal form (CNF) and evaluating the influence of CNF transformations on subsequent feature-model analyses using SAT and #SAT solvers.

### Replication Package

#### Getting Started

First, [install Docker](https://docs.docker.com/get-docker/) on a 64-bit Linux 5.x system. On Arch Linux, for example, run:

```
usermod -aG docker $(whoami) # then, log out and in again
sudo pacman -S docker
systemctl enable docker
systemctl start docker
```

Then, set the parameters in `params.ini` and run the evaluation with `sudo ./run.sh` (`sudo` is recommended to avoid permission issues with files created by Docker).
On a remote machine, run `screen -dmSL evaluation sudo ./run.sh` and press `Ctrl A, D` to detach from an SSH session (run `screen -x evaluation` to re-attach and `sudo killall containerd dockerd kclause python3 java bash` to stop).
To re-run the evaluation, run `sudo ./clean.sh && sudo ./run.sh`.
You can control which stages to (re-)run by prepolutating/removing files in the `data` directory.
For an overview over the individual stages, see the source code of `run.sh`.
To mimic the behaviour of the [feature-model-repository-pipeline](https://github.com/ekuiter/feature-model-repository-pipeline), set `SKIP_ANALYSIS=y` in `params.ini`.

The transformed DIMACS files are stored in the `data/dimacs` directory, named after the following scheme:

```
[project],[version],[iteration],[source],[transformation].dimacs
```

The time measurements are stored in `data/results_*.csv`, errors in `data/error_*.log`.

#### Im-/Export

To im-/export preconfigured Docker containers (download available [here](https://cloud.ovgu.de/s/pLyGicS95Z98bzg)), run `./import.sh` and `./export.sh`, respectively.
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
