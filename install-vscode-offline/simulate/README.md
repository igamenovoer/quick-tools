# VS Code Offline Simulation Environment

This directory contains scripts and configurations to simulate an offline VS Code environment using Docker or Podman. This is useful for testing the offline installation and connection process without needing a physical air-gapped machine.

## Contents

- **Docker/Podman Configuration**:
  - `server.Dockerfile`: Dockerfile for the simulated remote server (SSH target).
  - `terminal.Dockerfile`: Dockerfile for the simulated client terminal.
  - `podman-compose-both.yaml`: Compose file to run both server and terminal containers using Podman.

- **Build & Run Scripts**:
  - `build-server-docker.ps1`: Script to build the server container image.
  - `build-terminal-docker.ps1`: Script to build the terminal container image.
  - `start-both.ps1`: Script to start both containers.
  - `launch-vscode-in-terminal-container.ps1`: Helper to launch VS Code inside the terminal container.

- **Subdirectories**:
  - `checks/`: Scripts for verifying the environment.
  - `guides/`: Documentation and guides for the simulation.
  - `helper-scripts/`: Additional utility scripts.
  - `vscode/`: Configuration or resources related to VS Code within the simulation.
  - `deprecated/`: Old or unused scripts.
