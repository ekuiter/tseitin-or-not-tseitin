# Tseitin or not Tseitin? The Impact of CNF Transformations on Feature-Model Analyses

This repository provides Docker-based automation scripts for investigating transformations of feature-model formulas into conjunctive normal form (CNF) and evaluating the impact of such CNF transformations on subsequent feature-model analyses using SAT and #SAT solvers.

The repository has several purposes:
* First, it serves as the replication package for our ASE'22 paper "Tseitin or not Tseitin? The Impact of CNF Transformations on Feature-Model Analyses" (authored by Elias Kuiter, Sebastian Krieter, Chico Sundermann, Thomas Thüm, and Gunter Saake).
* Second, it can be used to build a repository of feature models for Kconfig-based open-source projects (superseding [ekuiter/feature-model-repository-pipeline](https://github.com/ekuiter/feature-model-repository-pipeline)).
* Third, it demonstrates how to apply the [FeatJAR](https://github.com/FeatJAR) infrastructure for authoring reproducible evaluations concerned with feature-model analysis.

To support the first two use cases, we ship `params-ase22.ini` for replicating the evaluation of our ASE'22 paper and `params-repo.ini` for extracting a feature-model repository.

## Getting Started

Regardless of the use case, these steps should be followed to set up the automation correctly.

* First, [install Docker](https://docs.docker.com/get-docker/) on a 64-bit Linux 5.x system. On Arch Linux, for example, run:
    ```
    usermod -aG docker $(whoami) # then, log out and in again
    sudo pacman -S docker
    systemctl enable docker
    systemctl start docker
    ```
* Then, set the evaluation parameters in `params.ini` (i.e., choose one of the predefined `params-*.ini`).
* Finally, run the evaluation with `sudo ./run.sh` (`sudo` is recommended to avoid permission issues with files created by Docker).
* On a remote machine, run `screen -dmSL evaluation sudo ./run.sh` and press `Ctrl A, D` to detach from an SSH session (run `screen -x evaluation` to re-attach and `sudo killall containerd dockerd kclause python3 java bash` to stop).
* To re-run the evaluation, run `sudo ./clean.sh && sudo ./run.sh`.

You can control which stages to (re-)run by prepolutating/removing files in the `data` directory.
For an overview over the individual stages, see the source code of `run.sh`.

### Replication Package (`params-ase22.ini`)

(todo)

The time measurements are stored in `data/results_*.csv`, errors in `data/error_*.log`.

### Feature Model Repository (`params-repo.ini`)

To build a repository of feature models and DIMACS files, acting like [ekuiter/feature-model-repository-pipeline](https://github.com/ekuiter/feature-model-repository-pipeline), set `SKIP_ANALYSIS=y` in `params.ini`.

The transformed DIMACS files are stored in the `data/dimacs` directory, named after the following scheme:

```
[project],[version],[iteration],[source],[transformation].dimacs
```

## Advanced Usage

### Im-/Export

To im-/export preconfigured Docker containers (download available [here](https://cloud.ovgu.de/s/pLyGicS95Z98bzg)), run `./import.sh` and `./export.sh`, respectively.
(This ensures the reproduceability of our results even when the Docker files fail to build from scratch.)

### Debugging

To access the evaluation's Docker container while it is running (e.g., to `tail -f` the log file), run (where `$reader = kconfigreader|kclause`):

```
docker exec -it $(docker ps --filter name=$reader --format "{{.ID}}") /bin/bash
```

To start an interactive session in a (not already running) Docker container:

```
docker run -it $reader /bin/bash
```

### Evaluation results

The results of the evaluation for our ASE'22 paper are available [here](https://cloud.ovgu.de/s/pLyGicS95Z98bzg).
