FROM node:22-slim

# System packages matching pen-base
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl wget git make \
    jq \
    ca-certificates \
    ripgrep \
    unzip zip \
    && rm -rf /var/lib/apt/lists/*

# fzf is not in debian slim's default repos at a recent version; install via binary release
RUN ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in \
      amd64)  FZF_ARCH=amd64 ;; \
      arm64)  FZF_ARCH=arm64 ;; \
      *) echo "error: unsupported architecture: $ARCH" >&2; exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/junegunn/fzf/releases/download/v0.67.0/fzf-0.67.0-linux_${FZF_ARCH}.tar.gz" \
      | tar -xzf - -C /usr/local/bin

# World-writable home dir for non-root users (host UID passed via --user at runtime)
RUN mkdir -p /home/pen && chmod 777 /home/pen

WORKDIR /workspace

# Cursor Agent CLI (official lab tarball; version pin — bump when upgrading)
ARG CURSOR_AGENT_VERSION=2026.03.30-a5d3e17
RUN ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in \
      amd64) CUR_ARCH=x64 ;; \
      arm64) CUR_ARCH=arm64 ;; \
      *) echo "error: unsupported architecture: $ARCH" >&2; exit 1 ;; \
    esac && \
    mkdir -p /opt/cursor-agent && \
    curl -fsSL "https://downloads.cursor.com/lab/${CURSOR_AGENT_VERSION}/linux/${CUR_ARCH}/agent-cli-package.tar.gz" \
      | tar -xzf - -C /opt/cursor-agent && \
    ln -sf /opt/cursor-agent/dist-package/cursor-agent /usr/local/bin/cursor-agent && \
    ln -sf /opt/cursor-agent/dist-package/cursor-agent /usr/local/bin/agent
