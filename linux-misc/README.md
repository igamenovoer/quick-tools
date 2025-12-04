# Linux Miscellaneous Scripts

A collection of utility scripts for various Linux system administration and maintenance tasks.

## Contents

- **System & Hardware**:
  - `create_ramdisk.sh`: Script to create a RAM disk.
  - `fstab-mount-all-partitions.bash`: Helper to mount partitions defined in fstab.
  - `fix-time-sync.bash` / `make-time-compatible-with-windows.bash`: Scripts to fix time synchronization issues, especially useful for dual-boot systems with Windows.
  - `add-users-to-group.sh`: Helper script to add users to a specific group.

- **Software & Updates**:
  - `switch-ubuntu-software-repo.sh`: Script to switch Ubuntu software repositories (mirrors).
  - `apt-change-source.sh`: Changes APT sources to a different mirror.
  - `apt-set-proxy.sh` / `apt-unset-proxy.sh`: Scripts to set or unset APT proxy configuration.
  - `install-useful-apps.sh`: Installs a collection of useful applications.
  - `upgrade-vscode.sh`: Script to upgrade Visual Studio Code.
  - `getpack.bash`: Utility for package management (details may vary).

- **SSH & Network**:
  - `add-my-keys-to-ssh-agent.sh`: Automates adding SSH keys to the agent.
  - `upload-file-via-rsync.sh`: Helper for uploading files using rsync.
