FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --allow-unauthenticated \
    default-jre \
    libgmpxx4ldbl \
    lib32z1 \
    bc \
    dos2unix
WORKDIR /home
COPY solve.sh sat* sharpsat* *.jar ./
RUN chmod +x *.sh && dos2unix *.sh