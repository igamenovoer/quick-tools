#!/bin/bash
# Script to add SSH private keys to ssh-agent
# Source this script in your shell to add all ssh keys:  source ~/add-my-keys.sh

# Start ssh-agent if not already running
if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)"
fi

# Add all private keys from ~/.ssh/
# This will prompt for passphrases if keys are encrypted
echo "Adding SSH keys to agent..."

# Add id_ed25519 if it exists
if [ -f ~/.ssh/id_ed25519 ]; then
    echo "Adding id_ed25519..."
    ssh-add ~/.ssh/id_ed25519
fi

# Add id_rsa if it exists
if [ -f ~/.ssh/id_rsa ]; then
    echo "Adding id_rsa..."
    ssh-add ~/.ssh/id_rsa
fi

# Add id_ecdsa if it exists
if [ -f ~/.ssh/id_ecdsa ]; then
    echo "Adding id_ecdsa..."
    ssh-add ~/.ssh/id_ecdsa
fi

# Add id_dsa if it exists
if [ -f ~/.ssh/id_dsa ]; then
    echo "Adding id_dsa..."
    ssh-add ~/.ssh/id_dsa
fi

echo ""
echo "Keys currently in agent:"
ssh-add -l
