# 파일명: Dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Buildroot 필수 의존성 패키지 설치
RUN apt-get update && apt-get install -y \
    build-essential bash bc binutils bzip2 cpio file git \
    graphviz gzip libncurses5-dev locales make patch perl \
    python3 python3-matplotlib rsync sed tar unzip wget \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8

# 호스트의 UID와 GID를 전달받기 위한 변수 정의 (기본값 1000)
ARG USER_ID=1000
ARG GROUP_ID=1000

# 호스트 사용자와 동일한 UID/GID를 가진 builduser 생성
RUN groupadd -g ${GROUP_ID} builduser && \
    useradd -u ${USER_ID} -g builduser -ms /bin/bash builduser

USER builduser
WORKDIR /home/builduser
