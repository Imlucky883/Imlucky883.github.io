---
layout: post
title: Tools Installation in RHEL Node
categories: [DevOps]
tags: [rhel, linux, devops, kubernetes, containers]
---

Setting up a fresh Red Hat Enterprise Linux (RHEL) worker or bastion node requires provisioning essential CLI tools, container engines, and orchestration utilities.

Whether configuring a new development environment or bootstrapping a cluster management node, having a reproducible installation workflow saves time and avoids dependency conflicts. Here is a step-by-step setup guide for the essential toolset.

### The Toolset Overview

The environment is configured with seven primary utilities covering containers, cluster management, automation, and modern command-line productivity:
- **Podman & Skopeo**: Daemonless OCI container runtime and remote image management.
- **fzf**: General-purpose interactive command-line fuzzy finder.
- **eza**: Modern, fast replacement for `ls` with Git support and file icons.
- **Helm**: The package manager for Kubernetes application deployments.
- **k9s**: Terminal UI for navigating, monitoring, and managing Kubernetes clusters.
- **Python 3.11**: Modern Python runtime with build headers and package manager.
- **just**: Command runner and modern recipe alternative to `make`

---

### Step-by-Step Installation

#### 1. Podman & Skopeo

RHEL distributes container management utilities via the modular `container-tools` Application Stream. Resetting and enabling the explicit stream ensures clean package resolution without conflicting container runtimes:

```bash
# Reset and enable the container-tools module stream
sudo dnf module reset -y container-tools
sudo dnf module enable -y container-tools:rhel8

# Install Podman, Skopeo, and companion tools
sudo dnf install -y podman skopeo
```

#### 2. Fuzzy Finder(fzf)

fzf is packaged directly in EPEL and standard RHEL repositories
```bash
sudo dnf install -y fzf
```
To enable shell key bindings (Ctrl + R for fuzzy history search, Ctrl + T for fast file lookup), add the shell integration to your ~/.bashrc or ~/.zshrc
```bash
# For Bash
source /usr/share/fzf/shell/key-bindings.bash 2>/dev/null

# For Zsh
source /usr/share/fzf/shell/key-bindings.zsh 2>/dev/null
```

#### 3. Modern Directory Listing (eza)

eza is a Rust-based, actively maintained fork of exa. Installing the precompiled GNU binary ensures you do not need the full Rust/Cargo build toolchain on the server
```bash
# Download the binary archive
wget [https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz](https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz)

# Extract the archive
tar -xzf eza_x86_64-unknown-linux-gnu.tar.gz

# Make executable and move to system PATH
sudo chmod +x eza
sudo chown root:root eza
sudo mv eza /usr/local/bin/

# Clean up archive
rm -f eza_x86_64-unknown-linux-gnu.tar.gz
```
Set drop-in aliases in ~/.bashrc or ~/.zshrc
```bash
alias ls='eza --icons --group-directories-first --color=always'
alias ll='eza -la --icons --group-directories-first --color=always --git'
alias lt='eza --tree --level=2 --icons --group-direc`tories-first --color=always'
```
#### 4. Kubernetes Package Manager (Helm)

Helm uses an automated upstream installation script to detect system architecture and fetch the binary
```bash
# Run the official installation script
curl -fsSL [https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3](https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3) | bash
```

Enable command completion in your active shell
```bash
# For Bash
helm completion bash | sudo tee /etc/bash_completion.d/helm > /dev/null

# For Zsh
echo 'source <(helm completion zsh)' >> ~/.zshrc
```

#### 5. Kubernetes Terminal UI (k9s)

k9s provides real-time cluster observation directly in your terminal. Installing via Webinstall (webi) fetches the precompiled release binary to ~/.local/bin
```bash
# Install k9s binary
curl -sS [https://webinstall.dev/k9s](https://webinstall.dev/k9s) | bash

# Ensure user binary path is exported
export PATH="$HOME/.local/bin:$PATH"
```

#### 6. Python 3.11 Runtime & Devel Headers

RHEL allows installing modern Python packages side-by-side with system packages without breaking system utilities that rely on default Python
```bash
sudo yum install -y python3.11 python3.11-devel python3.11-pip
```
Verify your Python 3.11 runtime and package manager:
```bash
python3.11 --version
python3.11 -m pip --version
```

#### 7. Command Runner (just)
just provides a streamlined command runner alternative to make without build-system overhead:
```bash
# Download and install just directly to /usr/local/bin
curl --proto '=https' --tlsv1.2 -sSf [https://just.systems/install.sh](https://just.systems/install.sh) | sudo bash -s -- --to /usr/local/bin
```
### Verification Checklist

To confirm all tools are installed and accessible in your shell $PATH, run this loop
```bash
for cmd in podman skopeo fzf eza helm k9s python3.11 just; do
  printf "%-12s: %s\n" "$cmd" "$(command -v $cmd || echo 'NOT FOUND')"
done
```





















