# Installation Scripts

This directory contains scripts for installing various software and configuring system settings.

## Contents

- **Docker & Containers**:
  - `install-docker.sh`: Script to install Docker.
  - `add-users-to-docker.sh`: Adds users to the Docker group.
  - `install-nvidia-container-toolkit.sh`: Installs the NVIDIA Container Toolkit for GPU support in containers.
  - `install-mermaid-cli.sh`: Installs Mermaid CLI.

- **System Configuration**:
  - `add-users-to-group.sh`: Helper script to add users to a specific group.
  - `apt-change-source.sh`: Changes APT sources to a different mirror.
  - `apt-set-proxy.sh` / `apt-unset-proxy.sh`: Scripts to set or unset APT proxy configuration.
  - `install-useful-apps.sh`: Installs a collection of useful applications.

- **NVIDIA Tools**:
  - `install-nsys.sh`: Installs NVIDIA Nsight Systems.
  - `setup-ncu-permissions.sh`: Sets up permissions for NVIDIA Nsight Compute.
  - `NCU_PERMISSIONS_GUIDE.md`: Guide for configuring permissions for NVIDIA Nsight Compute.
