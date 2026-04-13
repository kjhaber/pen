FROM node:22-alpine

# System packages: standard unix utilities + dev tools
RUN apk add --no-cache \
    bash curl wget git make \
    jq \
    ca-certificates \
    ripgrep fzf \
    unzip zip

# World-writable home dir for non-root users (host UID passed via --user at runtime)
RUN mkdir -p /home/pen && chmod 777 /home/pen

WORKDIR /workspace
