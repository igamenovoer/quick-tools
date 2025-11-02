#!/bin/bash

# this script setup proxy for apt
# it accepts the proxy (e.g., http://127.0.0.1:7890) as an argument
# if the proxy is not given, try to use http_proxy environment variable
# if proxy is available, add it to /etc/apt/apt.conf.d/proxy.conf

# am I root?
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

http_proxy_from_env=$(printenv http_proxy)
echo "got http_proxy from env: $http_proxy_from_env"

# Get proxy from argument or environment
if [ "$#" -eq 1 ]; then
  USER_PROXY=$1
elif [ -n "$http_proxy_from_env" ]; then
  USER_PROXY=$http_proxy_from_env
else
  echo "No proxy specified and http_proxy environment variable not set"
  echo "Usage: $0 <proxy>"
  exit 1
fi

# add proxy to apt
echo "Setting up proxy for apt"
echo "Acquire::http::Proxy \"$USER_PROXY\";" >> /etc/apt/apt.conf.d/proxy.conf
echo "Acquire::https::Proxy \"$USER_PROXY\";" >> /etc/apt/apt.conf.d/proxy.conf

echo "Proxy set to $USER_PROXY, /etc/apt/apt.conf.d/proxy.conf is updated"
cat /etc/apt/apt.conf.d/proxy.conf