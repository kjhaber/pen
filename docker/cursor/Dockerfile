FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# System packages: standard unix utilities + dev tools (match pen-claude baseline)
RUN apt-get update && apt-get install -y \
    curl wget git make \
    vim nano less \
    jq \
    build-essential ca-certificates gnupg \
    python3 python3-pip python3-venv \
    ripgrep fzf \
    unzip zip \
    && rm -rf /var/lib/apt/lists/*

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

# World-writable home dir for non-root users (host UID passed via --user at runtime)
RUN mkdir -p /home/pen && chmod 777 /home/pen

WORKDIR /workspace
