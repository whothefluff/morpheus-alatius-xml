FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# Install dependencies for compiling and for the data generation scripts
RUN apt-get update -qq && apt-get install -qq -y \
    build-essential \
    flex \
    perl

ADD . /morpheus
WORKDIR /morpheus

# make executable
RUN chmod +x ./update.sh && \
    # fix line endings
    sed -i 's/\r$//' ./update.sh

# do the same for this other sript
RUN chmod +x stemlib/Greek/getentities.pl && \
    sed -i 's/\r$//' stemlib/Greek/getentities.pl

RUN cd src/ && \
    make clean && \
    make && \
    make install && \
    cd .. && \
    ./update.sh && \
    ./update.sh && \
    echo "salve" | MORPHLIB=stemlib bin/cruncher -L && \
    cd ..
