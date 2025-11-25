FROM ubuntu:24.04

# Build arguments for SSH user configuration
ARG SSH_USERNAME=vscode-tester
ARG SSH_PASSWORD=123456

# Non-interactive apt/dpkg
ENV DEBIAN_FRONTEND=noninteractive

# Use Aliyun mirrors for faster apt in China / Asia (Ubuntu 24.04 uses deb822 ubuntu.sources).
RUN set -eux; \
    if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
      sed -i 's|http://archive.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|g; s|http://security.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources; \
    fi; \
    if [ -f /etc/apt/sources.list ]; then \
      sed -i 's|http://archive.ubuntu.com/ubuntu|http://mirrors.aliyun.com/ubuntu|g; s|http://security.ubuntu.com/ubuntu|http://mirrors.aliyun.com/ubuntu|g' /etc/apt/sources.list || true; \
    fi

# Install system packages via apt
# This requires internet during build but keeps the Dockerfile simple
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        unzip \
        sudo \
        locales \
        fonts-dejavu \
        libx11-6 \
        libxkbfile1 \
        libsecret-1-0 \
        libgtk-3-0 \
        libxss1 \
        libnss3 \
        libasound2t64 \
        libgbm1 \
        x11-apps \
        openssh-client \
        openssh-server \
        bash; \
    rm -rf /var/lib/apt/lists/*; \
    echo "==> System packages installed successfully"

# Configure a basic UTF-8 locale
RUN set -eux; \
    if command -v locale-gen >/dev/null 2>&1; then \
        locale-gen en_US.UTF-8 || true; \
        update-locale LANG=en_US.UTF-8 || true; \
    fi
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Create non-root SSH user with sudo privileges
ARG SSH_USERNAME
ARG SSH_PASSWORD
RUN set -eux; \
    useradd -m -s /bin/bash "${SSH_USERNAME}"; \
    echo "${SSH_USERNAME}:${SSH_PASSWORD}" | chpasswd; \
    usermod -aG sudo "${SSH_USERNAME}"; \
    echo "${SSH_USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${SSH_USERNAME}"; \
    chmod 440 "/etc/sudoers.d/${SSH_USERNAME}"

# Configure SSH server for X11 forwarding
ARG SSH_USERNAME
RUN set -eux; \
    mkdir -p /var/run/sshd; \
    mkdir -p "/home/${SSH_USERNAME}/.ssh"; \
    chmod 700 "/home/${SSH_USERNAME}/.ssh"; \
    chown "${SSH_USERNAME}:${SSH_USERNAME}" "/home/${SSH_USERNAME}/.ssh"; \
    # Enable X11 forwarding and other SSH settings
    sed -i 's/#X11Forwarding yes/X11Forwarding yes/' /etc/ssh/sshd_config || echo 'X11Forwarding yes' >> /etc/ssh/sshd_config; \
    sed -i 's/#X11UseLocalhost yes/X11UseLocalhost no/' /etc/ssh/sshd_config || echo 'X11UseLocalhost no' >> /etc/ssh/sshd_config; \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config; \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config; \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config || echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config; \
    echo 'UseDNS no' >> /etc/ssh/sshd_config; \
    # Generate SSH host keys
    ssh-keygen -A

# Copy terminal-specific packages from pkgs/terminal/
# Required files to be pre-downloaded and placed here:
# - pkgs/terminal/vscode-linux-*.tar.gz - VS Code tarball (REQUIRED)
COPY pkgs/terminal/ /pkgs-terminal/

# Copy shared VS Code extensions from pkgs/extensions/
# These extensions will be installed in both terminal and server containers
COPY pkgs/extensions/ /pkgs-extensions/

# Install VS Code from offline tarball in pkgs/terminal/
# The tarball must be pre-downloaded and placed in pkgs/terminal/
ARG SSH_USERNAME
RUN set -eux; \
    VSCODE_INSTALL_DIR="/home/${SSH_USERNAME}/.local/vscode"; \
    if ls /pkgs-terminal/vscode-linux-*.tar.gz >/dev/null 2>&1; then \
        echo "==> Installing VS Code from offline tarball"; \
        VSCODE_TARBALL=$(ls /pkgs-terminal/vscode-linux-*.tar.gz | head -1); \
        echo "==> Using tarball: $(basename ${VSCODE_TARBALL})"; \
        mkdir -p "${VSCODE_INSTALL_DIR}"; \
        tar -xzf "${VSCODE_TARBALL}" -C "${VSCODE_INSTALL_DIR}" --strip-components=1; \
        ln -sf "${VSCODE_INSTALL_DIR}/bin/code" /usr/local/bin/code; \
        chown -R "${SSH_USERNAME}:${SSH_USERNAME}" "${VSCODE_INSTALL_DIR}"; \
        # Display installed version
        VERSION_INFO=$(su -c "${VSCODE_INSTALL_DIR}/bin/code --version" "${SSH_USERNAME}" 2>/dev/null | head -1 || echo "unknown"); \
        echo "==> VS Code ${VERSION_INFO} installed successfully"; \
    else \
        echo "ERROR: No VS Code tarball found in /pkgs-terminal"; \
        echo "Required file: pkgs/terminal/vscode-linux-x64.tar.gz (or similar)"; \
        echo "Download from: https://code.visualstudio.com/download"; \
        exit 1; \
    fi

# Install VS Code extensions from shared extensions directory (without using VS Code CLI)
ARG SSH_USERNAME
RUN set -eux; \
    EXT_DIR="/home/${SSH_USERNAME}/.vscode/extensions"; \
    mkdir -p "${EXT_DIR}"; \
    if ls /pkgs-extensions/*.vsix >/dev/null 2>&1; then \
        echo "==> Installing VS Code extensions from /pkgs-extensions (manual unzip)"; \
        EXTENSION_COUNT=$(ls /pkgs-extensions/*.vsix | wc -l); \
        echo "==> Found ${EXTENSION_COUNT} extension(s)"; \
        for VSIX in /pkgs-extensions/*.vsix; do \
            VSIX_BASENAME=$(basename "${VSIX}"); \
            EXT_NAME="${VSIX_BASENAME%.vsix}"; \
            TARGET_DIR="${EXT_DIR}/${EXT_NAME}"; \
            echo "==> Installing: ${VSIX_BASENAME} -> ${TARGET_DIR}"; \
            rm -rf "${TARGET_DIR}"; \
            mkdir -p "${TARGET_DIR}"; \
            unzip -q "${VSIX}" -d "${TARGET_DIR}"; \
            if [ -d "${TARGET_DIR}/extension" ]; then \
                echo "    -> Flattening 'extension/' payload into ${TARGET_DIR}"; \
                cp -a "${TARGET_DIR}/extension/." "${TARGET_DIR}/"; \
                rm -rf "${TARGET_DIR}/extension"; \
            fi; \
        done; \
        chown -R "${SSH_USERNAME}:${SSH_USERNAME}" "${EXT_DIR}"; \
        echo "==> Extensions installed under ${EXT_DIR}"; \
    else \
        echo "==> No .vsix extension files found in /pkgs-extensions"; \
        echo "==> VS Code will run without extensions"; \
    fi

# SSH key for connecting to the remote server container
# The private key stays only in the terminal image; the public key is baked
# into the remote server image for password-less SSH.
ARG SSH_USERNAME
COPY helper-scripts/vscode_ssh_key /home/${SSH_USERNAME}/.ssh/id_ed25519
COPY helper-scripts/vscode_ssh_key.pub /home/${SSH_USERNAME}/.ssh/id_ed25519.pub
RUN set -eux; \
    chown -R "${SSH_USERNAME}:${SSH_USERNAME}" "/home/${SSH_USERNAME}/.ssh"; \
    chmod 700 "/home/${SSH_USERNAME}/.ssh"; \
    chmod 600 "/home/${SSH_USERNAME}/.ssh/id_ed25519"; \
    chmod 644 "/home/${SSH_USERNAME}/.ssh/id_ed25519.pub"; \
    # Convenience SSH config to skip host key prompts for the remote server container
    printf "Host vscode-remote\n  HostName vscode-remote\n  User ${SSH_USERNAME}\n  IdentityFile ~/.ssh/id_ed25519\n  StrictHostKeyChecking no\n  UserKnownHostsFile=/dev/null\n" > "/home/${SSH_USERNAME}/.ssh/config"; \
    chown "${SSH_USERNAME}:${SSH_USERNAME}" "/home/${SSH_USERNAME}/.ssh/config"; \
    chmod 600 "/home/${SSH_USERNAME}/.ssh/config"

# Create directory for VS Code settings
ARG SSH_USERNAME
RUN mkdir -p "/home/${SSH_USERNAME}/.config/Code/User" && \
    chown -R "${SSH_USERNAME}:${SSH_USERNAME}" "/home/${SSH_USERNAME}/.config"

# Expose SSH port for remote access with X11 forwarding
EXPOSE 22

ARG SSH_USERNAME
WORKDIR /home/${SSH_USERNAME}

# Create startup script that can run SSH server or VS Code
ARG SSH_USERNAME
ARG SSH_PASSWORD
RUN printf '#!/bin/bash\n\
set -e\n\
\n\
echo "==============================================="\n\
echo "VS Code Terminal Container (SSH + X11)"\n\
echo "==============================================="\n\
echo "User: %s"\n\
echo "Password: %s"\n\
echo ""\n\
echo "VS Code installed at: /home/%s/.local/vscode/bin/code"\n\
echo ""\n\
echo "Usage:"\n\
echo "  1. SSH with X11 forwarding:"\n\
echo "     ssh -X %s@<container>"\n\
echo "     code --disable-gpu --no-sandbox"\n\
echo ""\n\
echo "  2. Direct X11 (container with DISPLAY):"\n\
echo "     podman exec -it <container> bash"\n\
echo "     code --disable-gpu --no-sandbox"\n\
echo ""\n\
echo "  3. Run SSH server:"\n\
echo "     podman run -p 2222:22 <image> sshd"\n\
echo "     ssh -X -p 2222 %s@localhost"\n\
echo "==============================================="\n\
\n\
# Check if we should start SSH server or interactive shell\n\
if [ "$1" = "sshd" ] || [ "$1" = "/usr/sbin/sshd" ]; then\n\
    echo "Starting SSH server..."\n\
    exec /usr/sbin/sshd -D\n\
else\n\
    exec "$@"\n\
fi\n\
' "${SSH_USERNAME}" "${SSH_PASSWORD}" "${SSH_USERNAME}" "${SSH_USERNAME}" "${SSH_USERNAME}" > /usr/local/bin/docker-entrypoint.sh && \
    chmod +x /usr/local/bin/docker-entrypoint.sh

# Default to interactive bash shell
# To run SSH server instead: CMD ["sshd"]
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bash"]
