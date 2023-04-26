##############################################################################################
#  Copyright Accenture. All Rights Reserved.
#
#  SPDX-License-Identifier: Apache-2.0
##############################################################################################

# USAGE: 
# docker build . -t bevel-build
# docker run --network host -i -t bevel-build /bin/bash

FROM ubuntu:20.04

# Create working directory
WORKDIR /home/
ENV OPENSHIFT_VERSION='0.13.1'

RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        wget\
        curl \
        unzip \
        build-essential \
	    openssh-client \
        gcc \
        git \
        libdb-dev libleveldb-dev libsodium-dev zlib1g-dev libtinfo-dev \
        jq \
        npm

# Install OpenJDK-14
RUN wget https://download.java.net/java/GA/jdk14/076bab302c7b4508975440c56f6cc26a/36/GPL/openjdk-14_linux-x64_bin.tar.gz \
    && tar xvf openjdk-14_linux-x64_bin.tar.gz \
    && rm openjdk-14_linux-x64_bin.tar.gz


RUN apt-get update && apt-get install -y \
    python3-pip && \
    pip3 install --no-cache --upgrade pip setuptools wheel && \
    pip3 install ansible && \
    pip3 install jmespath && \
    pip3 install openshift==${OPENSHIFT_VERSION} && \
    apt-get clean && \
    ln -s /usr/bin/python3 /usr/bin/python && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g ajv-cli
RUN apt-get update && apt-get install -y python3-venv

RUN rm /etc/apt/apt.conf.d/docker-clean
RUN mkdir /etc/ansible/
RUN /bin/echo -e "[ansible_provisioners:children]\nlocal\n[local]\nlocalhost ansible_connection=local" > /etc/ansible/hosts

#Install aws cli Binary
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
          unzip awscliv2.zip && \
          ./aws/install && \
          rm -r awscliv2.zip

#Install eksctl Binary
ENV ARCH=amd64
ENV PLATFORM=Linux_$ARCH
RUN curl -sLO "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz" && \
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && \
    rm eksctl_$PLATFORM.tar.gz && \
    mv /tmp/eksctl /usr/local/bin

#Install kubectl Binary
RUN curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.22.17/2023-03-17/bin/linux/amd64/kubectl && \
    chmod +x ./kubectl && \
    mv kubectl /usr/local/bin/

#Install helm Binary
RUN curl -O https://get.helm.sh/helm-v3.6.2-linux-amd64.tar.gz && \
    tar -zxvf helm-v3.6.2-linux-amd64.tar.gz && \
    mv linux-amd64/helm /usr/local/bin/helm

#Install git
RUN apt-get update && \
    apt-get install git-all -y

RUN apt-get update && \
    apt-get install vim -y

# Copy the provisional script to build container
COPY ./run.sh /home
COPY ./reset.sh /home
RUN chmod 755 /home/run.sh
RUN chmod 755 /home/reset.sh
ENV PATH=/root/bin:/root/.local/bin/:$PATH
ENV JAVA_HOME=/home/jdk-14
ENV PATH=/home/jdk-14/bin:$PATH

# The mounted repo should contain a build folder with the following files
# 1) K8s config file as config
# 2) Network specific configuration file as network.yaml
# 3) Private key file which has write-access to the git repo

#path to mount the repo
VOLUME /home/bevel/


CMD ["/home/run.sh"]
