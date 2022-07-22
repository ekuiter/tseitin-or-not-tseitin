#!/bin/bash

source setup.sh

# The point of this file is to extract feature models and DIMACS files for as many Kconfig-based projects and versions of these projects as possible.
# More information on the systems below can be found in Berger et al.'s "Variability Modeling in the Systems Software Domain" (DOI: 10.1109/TSE.2013.34).
# Our general strategy is to read feature models for all tags (provided that tags give a meaningful history).
# We usually compile dumpconf against the project source to get the most accurate translation.
# Sometimes this is not possible, then we use dumpconf compiled for a Linux version with a similar Kconfig dialect (in most projects, the Kconfig parser is cloned&owned from Linux).
# You can also read feature models for any other tags/commits (e.g., for every commit that changes a Kconfig file), although usually very old versions won't work (because Kconfig might have only been introduced later) and very recent versions might also not work (because they use new/esoteric Kconfig features not supported by kconfigreader or dumpconf).

# Not included right now:
# https://github.com/coreboot/coreboot uses a modified Kconfig with wildcards for the source directive
# https://github.com/Freetz/freetz uses Kconfig, but cannot be parsed with dumpconf, so we use freetz-ng instead (which is newer anyway)
# https://github.com/rhuitl/uClinux is not so easy to set up, because it depends on vendor files
# https://github.com/zephyrproject-rtos/zephyr also uses Kconfig, but a modified dialect based on Kconfiglib, which is not compatible with kconfigreader
# https://github.com/solettaproject/soletta not yet included, many models available at https://github.com/TUBS-ISF/soletta-case-study

# Linux
git-checkout linux https://github.com/torvalds/linux
linux_env="ARCH=x86,SRCARCH=x86,KERNELVERSION=kcu,srctree=./,CC=cc,LD=ld,RUSTC=rustc"
for tag in $(git -C linux tag | grep -v rc | grep -v tree | grep -v v2.6.11); do
    if git -C linux ls-tree -r $tag --name-only | grep -q arch/i386; then
        run linux https://github.com/torvalds/linux $tag scripts/kconfig/*.o arch/i386/Kconfig $linux_env # in old versions, x86 is called i386
    else
        run linux https://github.com/torvalds/linux $tag scripts/kconfig/*.o arch/x86/Kconfig $linux_env
    fi
done

# axTLS
svn-checkout axtls svn://svn.code.sf.net/p/axtls/code/trunk
for tag in $(cd axtls; svn ls ^/tags); do
    run axtls svn://svn.code.sf.net/p/axtls/code/tags/$(echo $tag | tr / ' ') $(echo $tag | tr / ' ') config/scripts/config/*.o config/Config.in
done

# Buildroot
export BR2_EXTERNAL=support/dummy-external
export BUILD_DIR=buildroot
export BASE_DIR=buildroot
git-checkout buildroot https://github.com/buildroot/buildroot
for tag in $(git -C buildroot tag | grep -v rc | grep -v _ | grep -v -e '\..*\.'); do
    run buildroot https://github.com/buildroot/buildroot $tag c-bindings/linux/v4.17.$BINDING Config.in
done

# BusyBox
git-checkout busybox https://github.com/mirror/busybox
for tag in $(git -C busybox tag | grep -v pre | grep -v alpha | grep -v rc); do
    run busybox https://github.com/mirror/busybox $tag scripts/kconfig/*.o Config.in
done

# EmbToolkit
git-checkout embtoolkit https://github.com/ndmsystems/embtoolkit
for tag in $(git -C embtoolkit tag | grep -v rc | grep -v -e '-.*-'); do
    run embtoolkit https://github.com/ndmsystems/embtoolkit $tag scripts/kconfig/*.o Kconfig
done

# Fiasco
run fiasco https://github.com/kernkonzept/fiasco d393c79a5f67bb5466fa69b061ede0f81b6398db c-bindings/linux/v5.0.$BINDING src/Kconfig

# Freetz-NG
run freetz-ng https://github.com/Freetz-NG/freetz-ng 88b972a6283bfd65ae1bbf559e53caf7bb661ae3 c-bindings/linux/v5.0.$BINDING config/Config.in

# Toybox
git-checkout toybox https://github.com/landley/toybox
for tag in $(git -C toybox tag); do
    run toybox https://github.com/landley/toybox $tag c-bindings/linux/v2.6.12.$BINDING Config.in
done

# uClibc-ng
git-checkout uclibc-ng https://github.com/wbx-github/uclibc-ng
for tag in $(git -C uclibc-ng tag); do
    run uclibc-ng https://github.com/wbx-github/uclibc-ng $tag extra/config/zconf.tab.o extra/Configs/Config.in
done
