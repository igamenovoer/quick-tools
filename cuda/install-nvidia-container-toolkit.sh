#!/bin/bash

# do we have proxy set in http_proxy or HTTP_PROXY?
# if yes, use it as the proxy, set it to USER_PROXY
if [ -n "$http_proxy" ]; then
  USER_PROXY=$http_proxy
elif [ -n "$HTTP_PROXY" ]; then
  USER_PROXY=$HTTP_PROXY
fi

if [ -n "$USER_PROXY" ]; then
  echo "proxy setting is detected, using proxy $USER_PROXY"
fi

# if USER_PROXY is set, curl will use it as the proxy

if [ -n "$USER_PROXY" ]; then
  echo "Using proxy $USER_PROXY"
  curl \
    -x $USER_PROXY \
    -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

  curl \
    -x $USER_PROXY \
    -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
else
    curl \
        -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
fi

# if we have proxy, add it to apt
TMP_PROXY_CONF="_tmp_nvidia_proxy.conf"
if [ -n "$USER_PROXY" ]; then
  echo "Acquire::http::Proxy \"$USER_PROXY\";" | sudo tee /etc/apt/apt.conf.d/$TMP_PROXY_CONF
  echo "Acquire::https::Proxy \"$USER_PROXY\";" | sudo tee -a /etc/apt/apt.conf.d/$TMP_PROXY_CONF

  echo "apt proxy set to $USER_PROXY"
  echo "see /etc/apt/apt.conf.d/$TMP_PROXY_CONF"
fi

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# remove apt proxy
if [ -n "$USER_PROXY" ]; then
  sudo rm /etc/apt/apt.conf.d/$TMP_PROXY_CONF
  echo "temporary apt proxy $TMP_PROXY_CONF removed"
fi

echo "injecting nvidia-container-toolkit to docker runtime"
sudo nvidia-ctk runtime configure --runtime=docker

echo "restarting docker ..."
sudo systemctl restart docker

echo "nvidia-container-toolkit installed"