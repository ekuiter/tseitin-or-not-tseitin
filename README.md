# Tseitin or not Tseitin? The Impact of CNF Transformations on Feature-Model Analyses

This repository provides Docker-based automation scripts for investigating transformations of feature-model formulas into conjunctive normal form (CNF) and evaluating the impact of such CNF transformations on subsequent feature-model analyses using SAT and #SAT solvers.

The repository has several purposes:
* First, it serves as the replication package for our ASE'22 paper "Tseitin or not Tseitin? The Impact of CNF Transformations on Feature-Model Analyses" (authored by Elias Kuiter, Sebastian Krieter, Chico Sundermann, Thomas Thüm, and Gunter Saake).
* Second, it can be used to build a repository of feature models for Kconfig-based open-source projects (superseding [ekuiter/feature-model-repository-pipeline](https://github.com/ekuiter/feature-model-repository-pipeline)).
* Third, it demonstrates how to apply the [FeatJAR](https://github.com/FeatJAR) infrastructure for authoring reproducible evaluations concerned with feature-model analysis.

To support the first two use cases, we ship `params_ase22.ini` for replicating the evaluation of our ASE'22 paper and `params_repo.ini` for extracting a feature-model repository.

## Getting Started

Regardless of the use case, these steps should be followed to set up the automation correctly.

* First, install [Docker](https://docs.docker.com/get-docker/) and some other dependencies on a 64-bit Linux 5.x system or [WSL 2](https://docs.microsoft.com/de-de/windows/wsl/install).
    On Arch Linux, for example, run:
    ```
    usermod -aG docker $(whoami) # then, log out and in again
    sudo pacman -S git subversion docker
    systemctl enable docker
    systemctl start docker
    ```
* Clone this repository:
    ```
    git clone https://github.com/ekuiter/tseitin-or-not-tseitin.git && cd tseitin-or-not-tseitin
    ```
* Then, choose the evaluation parameters and an extraction script.
    For replicating our ASE'22 evaluation, run:
    ```
    cp input/params_ase22.ini input/params.ini
    cp input/extract_ase22.sh input/extract.sh
    ```
    For creating a feature model repository, run:
    ```
    cp input/params_repo.ini input/params.ini
    cp input/extract_repo.sh input/extract.sh
    ```
* Finally, run the script with `./run.sh`.
* On a remote machine, run `screen -dmSL tseitin ./run.sh` and press `Ctrl A, D` to detach from an SSH session (run `screen -x tseitin` to re-attach and `sudo killall containerd dockerd kclause python3 java bash` to stop).
* To re-run the script, run `./clean.sh && ./run.sh`.

You can control which stages to (re-)run by prepolutating/removing files in the `output` directory.
For an overview over the individual stages, see the source code of `run.sh`.

## File Structure

All input information is contained in the `input` directory, including:
* the evaluation parameters (`params.ini`)
* the extraction script (`extract.sh`)
* feature-model hierarchies available in `params.ini$HIERARCHIES` (`hierarchies`)
During script execution, the `input` directory will also be populated with clones of all evaluated projects' repositories.

All results are then stored in the `output` directory, including:
* extracted feature models (`models`), named after the following scheme:
    ```
    [project],[version],[iteration],[source].[xml|model]
    ```
* DIMACS files for said feature models (`dimacs`), named after the following scheme:
    ```
    [project],[version],[iteration],[source],[transformation].[xml|model]
    ```
* intermediate results (`intermediate` and `stage*`), useful for debugging
* measurement results (`results_*.csv`)
* warnings and errors (`error_*.log`)

The R script `ase22_evaluation.R` can be used to analyze and visualize the measurement results by running it within `output` as the working directory.

## Im-/Export

To im-/export preconfigured Docker containers (download available [here](https://cloud.ovgu.de/s/pLyGicS95Z98bzg)), run `./import.sh` and `./export.sh`, respectively.
(This ensures the reproduceability of our results even when the Docker files fail to build from scratch.)

## Debugging

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

