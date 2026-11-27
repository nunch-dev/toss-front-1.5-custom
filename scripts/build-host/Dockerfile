FROM ubuntu:22.04

ARG UID=1000
ARG GID=1000
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        bc bison build-essential ca-certificates ccache cpio curl file flex \
        g++-multilib gcc-multilib git git-lfs gnupg gperf imagemagick kmod \
        lib32ncurses5-dev lib32readline-dev lib32z1-dev libelf-dev libncurses5 \
        libsdl1.2-dev libssl-dev libxml2 libxml2-utils lz4 lzop openjdk-17-jdk-headless \
        patch pngcrush procps python-is-python3 python3 rsync schedtool \
        squashfs-tools unzip xsltproc xxd zip zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo \
    && chmod 755 /usr/local/bin/repo

RUN groupadd -g "${GID}" builder && useradd -m -u "${UID}" -g "${GID}" -s /bin/bash builder
USER builder
