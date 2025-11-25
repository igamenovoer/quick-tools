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

# Install system packages via apt-get (requires internet during build)
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        openssh-server \
        sudo \
        tar \
        curl \
        ca-certificates \
        bash; \
    rm -rf /var/lib/apt/lists/*; \
    echo "==> System packages installed successfully"

# Create SSH users with sudo privileges
ARG SSH_USERNAME
ARG SSH_PASSWORD
RUN set -eux; \
    # Create admin user (legacy, may be removed in future)
    useradd -m -s /bin/bash admin; \
    echo 'admin:admin' | chpasswd; \
    usermod -aG sudo admin; \
    # Create configurable SSH user
    useradd -m -s /bin/bash "${SSH_USERNAME}"; \
    echo "${SSH_USERNAME}:${SSH_PASSWORD}" | chpasswd; \
    usermod -aG sudo "${SSH_USERNAME}"

# Prepare SSH directories and permissions for both users
ARG SSH_USERNAME
RUN set -eux; \
    mkdir -p /var/run/sshd; \
    mkdir -p /home/admin/.ssh "/home/${SSH_USERNAME}/.ssh"; \
    chmod 700 /home/admin/.ssh "/home/${SSH_USERNAME}/.ssh"; \
    chown -R admin:admin /home/admin/.ssh; \
    chown -R "${SSH_USERNAME}:${SSH_USERNAME}" "/home/${SSH_USERNAME}/.ssh"

# SSH configuration for testing:
# - Disable root login
# - Enable password authentication (for this simulation)
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    echo 'UseDNS no' >> /etc/ssh/sshd_config

# Copy server-specific packages from pkgs/server/
# Required files to be pre-downloaded and placed here:
# - pkgs/server/vscode-server-linux-x64-*.tar.gz - VS Code Server tarball (REQUIRED)
# - pkgs/server/vscode-cli-alpine-x64-*.tar.gz - VS Code CLI tarball (REQUIRED)
COPY pkgs/server/ /pkgs-server/

# Copy shared VS Code extensions from pkgs/extensions/
# These extensions will be installed in both terminal and server containers
COPY pkgs/extensions/ /pkgs-extensions/

# Install VS Code Server for the configurable SSH user
# This pre-installs the server so Remote-SSH can connect without downloading
ARG SSH_USERNAME
RUN set -eux; \
    VSCODE_USER="${SSH_USERNAME}"; \
    VSCODE_HOME="/home/${VSCODE_USER}"; \
    VSCODE_SERVER_DIR="${VSCODE_HOME}/.vscode-server"; \
    \
    # Check for required tarballs
    if ! ls /pkgs-server/vscode-server-linux-x64-*.tar.gz >/dev/null 2>&1; then \
        echo "ERROR: No VS Code Server tarball found in /pkgs-server"; \
        echo "Required file: pkgs/server/vscode-server-linux-x64-<COMMIT>.tar.gz"; \
        echo "Download from: https://update.code.visualstudio.com/commit:<COMMIT>/server-linux-x64/stable"; \
        exit 1; \
    fi; \
    \
    if ! ls /pkgs-server/vscode-cli-alpine-x64-*.tar.gz >/dev/null 2>&1; then \
        echo "ERROR: No VS Code CLI tarball found in /pkgs-server"; \
        echo "Required file: pkgs/server/vscode-cli-alpine-x64-<COMMIT>.tar.gz"; \
        echo "Download from: https://update.code.visualstudio.com/commit:<COMMIT>/cli-alpine-x64/stable"; \
        exit 1; \
    fi; \
    \
    # Detect commit hash from tarball filenames
    SERVER_TARBALL=$(ls /pkgs-server/vscode-server-linux-x64-*.tar.gz | head -1); \
    CLI_TARBALL=$(ls /pkgs-server/vscode-cli-alpine-x64-*.tar.gz | head -1); \
    \
    # Extract commit hash from filename (format: vscode-server-linux-x64-COMMIT.tar.gz)
    VSCODE_COMMIT=$(basename "${SERVER_TARBALL}" | sed 's/vscode-server-linux-x64-//; s/.tar.gz//'); \
    \
    if [ -z "${VSCODE_COMMIT}" ] || [ "${VSCODE_COMMIT}" = "*" ]; then \
        echo "ERROR: Could not extract commit hash from tarball filename"; \
        echo "Expected format: vscode-server-linux-x64-<COMMIT>.tar.gz"; \
        exit 1; \
    fi; \
    \
    echo "==> Installing VS Code Server for user: ${VSCODE_USER}"; \
    echo "==> Commit: ${VSCODE_COMMIT}"; \
    echo "==> Server tarball: $(basename ${SERVER_TARBALL})"; \
    echo "==> CLI tarball: $(basename ${CLI_TARBALL})"; \
    \
    # Create directory structure for VS Code Server
    # Remote-SSH looks for files in this exact structure
    mkdir -p "${VSCODE_SERVER_DIR}/cli/servers/Stable-${VSCODE_COMMIT}/server"; \
    mkdir -p "${VSCODE_SERVER_DIR}/data/Machine"; \
    mkdir -p "${VSCODE_SERVER_DIR}/extensions"; \
    \
    # Place CLI tarball for cache detection
    # Remote-SSH checks for vscode-cli-${COMMIT}.tar.gz before downloading
    cp "${CLI_TARBALL}" "${VSCODE_SERVER_DIR}/vscode-cli-${VSCODE_COMMIT}.tar.gz"; \
    \
    # Create .done marker file (copy of CLI tarball)
    # This tells Remote-SSH that CLI is already downloaded
    cp "${CLI_TARBALL}" "${VSCODE_SERVER_DIR}/vscode-cli-${VSCODE_COMMIT}.tar.gz.done"; \
    \
    # Place server tarball with generic name (not commit-specific)
    # Remote-SSH looks for this generic name
    cp "${SERVER_TARBALL}" "${VSCODE_SERVER_DIR}/vscode-server.tar.gz"; \
    \
    # Extract server to the expected location
    # Remote-SSH will use this if it exists
    tar -xzf "${SERVER_TARBALL}" \
        -C "${VSCODE_SERVER_DIR}/cli/servers/Stable-${VSCODE_COMMIT}/server" \
        --strip-components=1; \
    \
    # Create configuration files
    echo '{}' > "${VSCODE_SERVER_DIR}/data/Machine/settings.json"; \
    \
    # Create .ready marker file
    touch "${VSCODE_SERVER_DIR}/cli/servers/Stable-${VSCODE_COMMIT}/server/.ready"; \
    \
    # Set proper ownership
    chown -R ${VSCODE_USER}:${VSCODE_USER} "${VSCODE_SERVER_DIR}"; \
    \
    # Verify installation
    if [ -f "${VSCODE_SERVER_DIR}/cli/servers/Stable-${VSCODE_COMMIT}/server/bin/code-server" ]; then \
        echo "==> VS Code Server installed successfully!"; \
        echo "==> Server binary: ${VSCODE_SERVER_DIR}/cli/servers/Stable-${VSCODE_COMMIT}/server/bin/code-server"; \
        echo "==> Cache files placed for offline Remote-SSH connection"; \
    else \
        echo "ERROR: Installation failed - code-server binary not found"; \
        exit 1; \
    fi

# Install VS Code extensions from shared extensions directory for the configurable SSH user
# Extensions will be available when connecting via Remote-SSH
ARG SSH_USERNAME
RUN set -eux; \
    VSCODE_USER="${SSH_USERNAME}"; \
    VSCODE_HOME="/home/${VSCODE_USER}"; \
    VSCODE_SERVER_DIR="${VSCODE_HOME}/.vscode-server"; \
    \
    # Find the VS Code Server commit hash from existing installation
    VSCODE_COMMIT=$(ls -1d ${VSCODE_SERVER_DIR}/cli/servers/Stable-* 2>/dev/null | head -1 | xargs basename | sed 's/Stable-//'); \
    \
    if [ -z "${VSCODE_COMMIT}" ]; then \
        echo "ERROR: Could not find VS Code Server installation"; \
        exit 1; \
    fi; \
    \
    VSCODE_SERVER_BIN="${VSCODE_SERVER_DIR}/cli/servers/Stable-${VSCODE_COMMIT}/server/bin/code-server"; \
    \
    if [ ! -f "${VSCODE_SERVER_BIN}" ]; then \
        echo "ERROR: VS Code Server binary not found at ${VSCODE_SERVER_BIN}"; \
        exit 1; \
    fi; \
    \
    if ls /pkgs-extensions/*.vsix >/dev/null 2>&1; then \
        echo "==> Installing VS Code Server extensions from /pkgs-extensions"; \
        EXTENSION_COUNT=$(ls /pkgs-extensions/*.vsix | wc -l); \
        echo "==> Found ${EXTENSION_COUNT} extension(s)"; \
        for VSIX in /pkgs-extensions/*.vsix; do \
            VSIX_NAME=$(basename "${VSIX}"); \
            echo "==> Installing: ${VSIX_NAME}"; \
            if su -c "${VSCODE_SERVER_BIN} --install-extension ${VSIX} --force --extensions-dir ${VSCODE_SERVER_DIR}/extensions" ${VSCODE_USER} 2>/dev/null; then \
                echo "    ✓ ${VSIX_NAME} installed"; \
            else \
                echo "    ✗ Failed to install ${VSIX_NAME}"; \
            fi; \
        done; \
        echo "==> Listing installed extensions:"; \
        su -c "${VSCODE_SERVER_BIN} --list-extensions --extensions-dir ${VSCODE_SERVER_DIR}/extensions" ${VSCODE_USER} 2>/dev/null || true; \
    else \
        echo "==> No .vsix extension files found in /pkgs-extensions"; \
        echo "==> VS Code Server will run without extensions"; \
    fi

# Inject the public SSH key for the configurable SSH user. The authorized_keys file
# may be shadowed by a volume mount; startup-info.sh will ensure it exists at container start.
ARG SSH_USERNAME
COPY helper-scripts/vscode_ssh_key.pub /etc/vscode-ssh-keys/${SSH_USERNAME}.pub

RUN set -eux; \
    mkdir -p /etc/vscode-ssh-keys; \
    chmod 644 "/etc/vscode-ssh-keys/${SSH_USERNAME}.pub"

# Generate SSH host keys
RUN ssh-keygen -A

# Expose SSH port
EXPOSE 22

# Simple startup info banner and one-time SSH key initialization for the configurable SSH user
ARG SSH_USERNAME
ARG SSH_PASSWORD
RUN printf '#!/bin/bash\n\
set -e\n\
\n\
echo "==================================="\n\
echo "VS Code Remote-SSH Server (Air-Gapped)"\n\
echo "==================================="\n\
echo "OS: Ubuntu 24.04"\n\
echo "Users:"\n\
echo "  admin / admin - SSH allowed"\n\
echo "  %s / %s - SSH + VS Code Server"\n\
echo "SSH Port: 22 (map from host)"\n\
echo "==================================="\n\
echo "VS Code Server pre-installed for user: %s"\n\
echo "Connect from VS Code using Remote-SSH extension"\n\
echo "==================================="\n\
echo "Example SSH connection:"\n\
echo "  ssh -p 4444 %s@localhost"\n\
echo "==================================="\n\
\n\
# Ensure the configured SSH user has the injected public key even if /home is a volume\n\
if [ -f "/etc/vscode-ssh-keys/%s.pub" ]; then\n\
  if [ ! -f "/home/%s/.ssh/authorized_keys" ]; then\n\
    mkdir -p "/home/%s/.ssh"\n\
    cat "/etc/vscode-ssh-keys/%s.pub" >> "/home/%s/.ssh/authorized_keys"\n\
    chown -R "%s:%s" "/home/%s/.ssh"\n\
    chmod 700 "/home/%s/.ssh"\n\
    chmod 600 "/home/%s/.ssh/authorized_keys"\n\
  fi\n\
fi\n\
' "${SSH_USERNAME}" "${SSH_PASSWORD}" "${SSH_USERNAME}" "${SSH_USERNAME}" "${SSH_USERNAME}" "${SSH_USERNAME}" "${SSH_USERNAME}" "${SSH_USERNAME}" "${SSH_USERNAME}" "${SSH_USERNAME}" "${SSH_USERNAME}" "${SSH_USERNAME}" "${SSH_USERNAME}" "${SSH_USERNAME}" > /usr/local/bin/startup-info.sh && \
    chmod +x /usr/local/bin/startup-info.sh

# Start SSH daemon and keep container running
CMD ["/bin/bash", "-c", "/usr/local/bin/startup-info.sh && /usr/sbin/sshd -D"]
