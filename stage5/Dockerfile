FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --allow-unauthenticated \
    default-jre \
    libgmpxx4ldbl \
    lib32z1 \
    bc
WORKDIR /home
COPY solve_cnf.sh sat* sharpsat* *.jar ./
RUN chmod +x *.sh