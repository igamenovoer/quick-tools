#!/bin/bash

# this script removes proxy settings for apt
# it removes the proxy configuration file created by apt-set-proxy.sh

# am I root?
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# remove proxy configuration file if it exists
if [ -f /etc/apt/apt.conf.d/proxy.conf ]; then
  echo "Removing apt proxy configuration"
  rm /etc/apt/apt.conf.d/proxy.conf
  echo "Proxy configuration removed"
else
  echo "No proxy configuration found"
fi
