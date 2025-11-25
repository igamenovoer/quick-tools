# Dockerfile for Ubuntu 24.04 SSH test environment
# Purpose: Test VS Code offline Remote-SSH installation

FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Update and install OpenSSH server and required utilities
RUN apt-get update && \
    apt-get install -y \
    openssh-server \
    sudo \
    tar \
    curl \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create testuser with password
RUN useradd -m -s /bin/bash testuser && \
    echo 'testuser:123456' | chpasswd && \
    usermod -aG sudo testuser

# Configure SSH
RUN mkdir -p /var/run/sshd && \
    mkdir -p /home/testuser/.ssh && \
    chmod 700 /home/testuser/.ssh && \
    chown -R testuser:testuser /home/testuser/.ssh

# SSH configuration for testing
# Enable password authentication and disable strict host key checking prompts
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    echo 'UseDNS no' >> /etc/ssh/sshd_config

# Create directory for VS Code Server (will be populated by install script)
RUN mkdir -p /home/testuser/.vscode-server && \
    chown -R testuser:testuser /home/testuser/.vscode-server

# Generate SSH host keys
RUN ssh-keygen -A

# Expose SSH port (will be mapped to 4444 on host)
EXPOSE 22

# Display system info on startup
RUN echo '#!/bin/bash\n\
echo "==================================="\n\
echo "VS Code SSH Test Environment"\n\
echo "==================================="\n\
echo "OS: Ubuntu 24.04"\n\
echo "Architecture: $(uname -m)"\n\
echo "User: testuser"\n\
echo "Password: 123456"\n\
echo "SSH Port: 22 (mapped to 4444 on host)"\n\
echo "==================================="\n\
echo "Connect with:"\n\
echo "  ssh -p 4444 testuser@localhost"\n\
echo "Or from VS Code Remote-SSH:"\n\
echo "  testuser@localhost:4444"\n\
echo "==================================="\n\
' > /usr/local/bin/startup-info.sh && \
    chmod +x /usr/local/bin/startup-info.sh

# Start SSH daemon and keep container running
CMD ["/bin/bash", "-c", "/usr/local/bin/startup-info.sh && /usr/sbin/sshd -D"]
