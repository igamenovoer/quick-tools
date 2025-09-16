#!/bin/bash

# Configure Git global user settings
git config --global user.name "igamenovoer"
git config --global user.email "igamenovoer@xx.com"

echo "Git global configuration updated:"
echo "User name: $(git config --global user.name)"
echo "User email: $(git config --global user.email)"