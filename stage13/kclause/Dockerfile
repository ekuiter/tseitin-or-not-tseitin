FROM ubuntu:18.04

# install (tested) dependencies of kmax/kclause and evaluation scripts
RUN apt-get update && apt-get install -y --allow-unauthenticated \
  git \
  subversion \
  python3-setuptools \
  python3-dev \
  flex \
  bison \
  bc \
  libssl-dev \
  libelf-dev \
  wget

# install (the tested version of) kmax/kclause
WORKDIR /home
RUN git clone https://github.com/paulgazz/kmax.git \
  && cd kmax \
  && git checkout c6e83a07d4f916267cb9e718c0b2de42ecfe4147 \
  && python3 setup.py install

# clone the analyzed projects
RUN git clone https://github.com/torvalds/linux linux
RUN git clone https://github.com/buildroot/buildroot buildroot
RUN git clone https://github.com/mirror/busybox busybox
RUN git clone https://github.com/ndmsystems/embtoolkit embtoolkit
RUN git clone https://github.com/kernkonzept/fiasco fiasco
RUN git clone https://github.com/Freetz-NG/freetz-ng freetz-ng
RUN git clone https://github.com/landley/toybox toybox
RUN git clone https://github.com/wbx-github/uclibc-ng uclibc-ng
RUN svn checkout svn://svn.code.sf.net/p/axtls/code/tags/release-2.0.0 axtls

# install dependencies of analyzed projects
RUN apt-get update && apt-get install -y --allow-unauthenticated \
  build-essential

# copy and set up
# - kextractor (which is compiled against the projects' Kconfig implementations)
# - IO and evaluation scripts
COPY kclause/kextractor.c kclause/*.py *.sh ./
RUN chmod +x *.sh