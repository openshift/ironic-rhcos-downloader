FROM docker.io/centos:centos7

RUN yum install -y epel-release && yum update -y && yum install -y qemu-img jq && yum clean all

COPY ./get-resource.sh /usr/local/bin/get-resource.sh
