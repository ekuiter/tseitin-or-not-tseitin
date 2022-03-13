#!/bin/bash

source extract_setup.sh

# The point of this file is to extract feature models for a representative selection of configurable systems based on the Kconfig configuration language.
# More information on the systems below can be found in Berger et al.'s "Variability Modeling in the Systems Software Domain" (DOI: 10.1109/TSE.2013.34).
# We usually compile dumpconf against the project source to get the most accurate translation.
# Sometimes this is not possible, then we use dumpconf compiled for a Linux version with a similar Kconfig dialect (in most projects, the Kconfig parser is cloned&owned from Linux).

# We have not included the following systems from the above paper:
# https://github.com/coreboot/coreboot uses a modified Kconfig with wildcards for the source directive
# https://github.com/Freetz/freetz uses Kconfig, but cannot be parsed with dumpconf, so we use freetz-ng instead (which is newer anyway)
# https://github.com/rhuitl/uClinux is not so easy to set up, because it depends on vendor files

# Iterate the process to improve accuracy of time measurement.
# Also, model/DIMACS files produced by kconfigreader have nondeterministic clause order.

# Run the analysis.
linux_env="ARCH=x86,SRCARCH=x86,KERNELVERSION=kcu,srctree=./,CC=cc,LD=ld,RUSTC=rustc"
run linux skip-model v2.6.12 scripts/kconfig/*.o arch/i386/Kconfig $linux_env
run linux skip-model v4.17 scripts/kconfig/*.o arch/x86/Kconfig $linux_env
run linux git v4.18 scripts/kconfig/*.o arch/x86/Kconfig $linux_env
run linux skip-model v5.0 scripts/kconfig/*.o arch/x86/Kconfig $linux_env
run axtls skip-checkout release-2.0.0 config/scripts/config/*.o config/Config.in
export BR2_EXTERNAL=support/dummy-external
export BUILD_DIR=/home/buildroot
export BASE_DIR=/home/buildroot
run buildroot git 2021.11.2 /home/data/c-bindings/linux/v4.17.$BINDING Config.in
run busybox git 1_35_0 scripts/kconfig/*.o Config.in
run embtoolkit git embtoolkit-1.8.0 scripts/kconfig/*.o Kconfig
run fiasco git 58aa50a8aae2e9396f1c8d1d0aa53f2da20262ed /home/data/c-bindings/linux/v5.0.$BINDING src/Kconfig
run freetz-ng git 5c5a4d1d87ab8c9c6f121a13a8fc4f44c79700af /home/data/c-bindings/linux/v5.0.$BINDING config/Config.in
run toybox git 0.8.6 /home/data/c-bindings/linux/v2.6.12.$BINDING Config.in
run uclibc-ng git v1.0.40 extra/config/zconf.tab.o extra/Configs/Config.in
