#/bin/bash

# require root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# do we have proxy set in http_proxy or HTTP_PROXY?
# if yes, use it as the proxy, set it to USER_PROXY
if [ -n "$http_proxy" ]; then
  USER_PROXY=$http_proxy
elif [ -n "$HTTP_PROXY" ]; then
  USER_PROXY=$HTTP_PROXY
fi

# install the latest docker
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings

# Add the key to the keyring:
echo "Adding Docker's official GPG key"

# if we have proxy, use it
if [ -n "$USER_PROXY" ]; then
  sudo curl \
    -x $USER_PROXY \
    -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
else
  sudo curl \
    -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
fi
sudo chmod a+r /etc/apt/keyrings/docker.asc

TMP_PROXY_CONF="_tmp_docker_proxy.conf"

# if we have proxy, add it to apt
if [ -n "$USER_PROXY" ]; then
  echo "Acquire::http::Proxy \"$USER_PROXY\";" | sudo tee /etc/apt/apt.conf.d/$TMP_PROXY_CONF
  echo "Acquire::https::Proxy \"$USER_PROXY\";" | sudo tee -a /etc/apt/apt.conf.d/$TMP_PROXY_CONF

  echo "apt proxy set to $USER_PROXY"
  echo "see /etc/apt/apt.conf.d/$TMP_PROXY_CONF"
fi

# Add the repository to Apt sources:
echo "Adding Docker's official repository to Apt sources"
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install Docker
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# remove apt proxy
if [ -n "$USER_PROXY" ]; then
  sudo rm /etc/apt/apt.conf.d/$TMP_PROXY_CONF
  echo "temporary apt proxy $TMP_PROXY_CONF removed"
fi