#!/bin/sh

# tools
sudo apt install -y jq yq sshpass libxcb-xinerama0 libxcb-xinput0 libxcb-cursor0 libxkbcommon-x11-0
sudo apt install -y ffmpeg tree

# install pixi tools only if pixi is available
if command -v pixi >/dev/null 2>&1; then
    pixi global install httpie aria2 yt-dlp plantuml graphviz
else
    echo "pixi not found; skipping pixi package installation"
fi

# install uv for managing pypi tools (for those not available in conda-forge, otherwise use pixi)
if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# activate uv
if [ -f "$HOME/.local/bin/env" ]; then
    . "$HOME/.local/bin/env"
else
    echo "uv activation file not found at $HOME/.local/bin/env; you may need to open a new shell or add ~/.local/bin to PATH."
fi

# install uv tools

