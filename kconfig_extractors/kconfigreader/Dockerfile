FROM ubuntu:14.04

# install (tested) dependencies of kconfigreader and evaluation scripts
RUN echo "deb https://repo.scala-sbt.org/scalasbt/debian all main" | sudo tee /etc/apt/sources.list.d/sbt.list
RUN echo "deb https://repo.scala-sbt.org/scalasbt/debian /" | sudo tee /etc/apt/sources.list.d/sbt_old.list
RUN apt-get update && apt-get install -y --allow-unauthenticated \
  git \
  subversion \
  openjdk-7-jdk \
  sbt=0.13.6 \
  wget

# install (the tested version of) kconfigreader
WORKDIR /home
RUN git clone https://github.com/ckaestne/kconfigreader.git \
  && cd kconfigreader \
  && git checkout 913bf3178af5a8ac8bedc5e8733561ed38280cf9 \
  && sbt mkrun

# clone the analyzed projects
RUN git clone https://github.com/torvalds/linux linux
RUN svn checkout svn://svn.code.sf.net/p/axtls/code/tags/release-2.0.0 axtls
RUN git clone https://github.com/buildroot/buildroot buildroot
RUN git clone https://github.com/mirror/busybox busybox
RUN git clone https://github.com/ndmsystems/embtoolkit embtoolkit
RUN git clone https://github.com/kernkonzept/fiasco fiasco
RUN git clone https://github.com/Freetz-NG/freetz-ng freetz-ng
RUN git clone https://github.com/landley/toybox toybox
RUN git clone https://github.com/wbx-github/uclibc-ng uclibc-ng

# install dependencies of analyzed projects
RUN apt-get update && apt-get install -y --allow-unauthenticated \
  flex \
  bison \
  build-essential \
  bc

# copy and set up
# - dumpconf (which is compiled against the projects' Kconfig implementations)
# - evaluation scripts
# - CNF transformer
COPY kconfigreader/TransformCNF.scala kconfigreader/src/main/scala/
RUN cd kconfigreader && sbt mkrun
COPY kconfigreader/dumpconf.c *.sh kconfigreader/transform* ./
RUN chmod +x *.sh