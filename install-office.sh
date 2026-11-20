#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -m) != x86_64 || ! -e /run/ostree-booted || $EUID == 0 ]]; then
    echo 'Run this as your regular user on installed x86_64 Fedora Kinoite.' >&2
    exit 1
fi

workdir=$(mktemp -d)
trap 'rm -rf -- "$workdir"' EXIT

download() {
    curl --proto '=https' --proto-redir '=https' --fail --silent --show-error \
        --location --retry 3 --output "$2" "$1"
}

install_craft_app() {
    local app=$1 version=$2 checksum=$3
    local bundle="$workdir/$app.flatpak"
    if flatpak info --user "ai.storyteller.$app" >/dev/null 2>&1; then
        return
    fi
    download "https://github.com/storytold/$app/releases/download/v$version/$app-$version-linux-x86_64.flatpak" "$bundle"
    printf '%s  %s\n' "$checksum" "$bundle" | sha256sum --check
    flatpak install --user --noninteractive --bundle "$bundle"
}

sudo -v
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user --noninteractive flathub com.discordapp.Discord com.dropbox.Client
install_craft_app wordcraft 0.18.1 7f3923f3537c020521318307428211d80848cd9ccb055265b23d6139216616a9
install_craft_app gridcraft 0.19.1 535289047c3891e5a238feaa186096ca3c0c283cdfde1e0fff72240f5f475d02

if [[ ! -e /etc/yum.repos.d/netbird.repo ]]; then
    sudo tee /etc/yum.repos.d/netbird.repo >/dev/null <<'REPO'
[netbird]
name=NetBird
baseurl=https://pkgs.netbird.io/yum/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.netbird.io/yum/repodata/repomd.xml.key
REPO
fi

packages=(netbird)
if ! rpm -q google-chrome-stable >/dev/null; then
    download https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm "$workdir/google-chrome.rpm"
    [[ $(rpm -qp --queryformat '%{NAME}.%{ARCH}' "$workdir/google-chrome.rpm") == google-chrome-stable.x86_64 ]]
    packages+=("$workdir/google-chrome.rpm")
fi
sudo rpm-ostree install --idempotent --allow-inactive "${packages[@]}"

echo 'Reboot to activate the host packages. Then run: sudo systemctl enable --now netbird && netbird up'
echo 'Launch Dropbox and Discord from the application menu to sign in.'
