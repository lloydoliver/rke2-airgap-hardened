#!/usr/bin/env bash

free -h

cat /proc/cpuinfo

sudo systemctl stop firewalld && sudo systemctl disable firewalld

swapoff -a
#sudo vi /etc/fstab

ip a | grep inet

hostname -f

dig www.google.com | grep "^www"

timedatectl
ntpq -p

df -h


