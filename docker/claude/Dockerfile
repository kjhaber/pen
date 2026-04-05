FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# System packages: standard unix utilities + dev tools
RUN apt-get update && apt-get install -y \
    curl wget git make \
    vim nano less \
    jq \
    build-essential ca-certificates gnupg \
    python3 python3-pip python3-venv \
    ripgrep fzf \
    unzip zip \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS (via NodeSource)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Go (official distribution, architecture-aware)
ARG GO_VERSION=1.24.2
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" \
      | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/home/pen/go"
ENV PATH="${GOPATH}/bin:${PATH}"

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# World-writable home dir for non-root users (host UID passed via --user at runtime)
RUN mkdir -p /home/pen && chmod 777 /home/pen

WORKDIR /workspace
