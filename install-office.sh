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
    download "https://github.com/storytold/$app/releases/download/v$version/$app-$version-linux-x86_64.flatpak" "$bundle" || return
    printf '%s  %s\n' "$checksum" "$bundle" | sha256sum --check || return
    flatpak install --user --noninteractive --bundle "$bundle"
}

install_netbird() {
    if [[ ! -e /etc/yum.repos.d/netbird.repo ]]; then
        sudo tee /etc/yum.repos.d/netbird.repo >/dev/null <<'REPO' || return
[netbird]
name=NetBird
baseurl=https://pkgs.netbird.io/yum/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.netbird.io/yum/repodata/repomd.xml.key
REPO
    fi
    sudo rpm-ostree install --idempotent --allow-inactive netbird || return
    echo 'If NetBird was newly staged, reboot. Then run: sudo systemctl enable --now netbird && netbird up'
}

failed=()
install_step() {
    local label=$1
    shift
    printf '\n==> %s\n' "$label"
    if "$@"; then
        printf 'OK: %s\n' "$label"
    else
        printf 'Failed: %s\n' "$label" >&2
        failed+=("$label")
    fi
}

install_step NetBird install_netbird

install_step Flathub flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
if rpm -q google-chrome-stable >/dev/null 2>&1 || flatpak info com.google.Chrome >/dev/null 2>&1; then
    echo 'OK: Google Chrome is already installed.'
else
    install_step 'Google Chrome' flatpak install --user --noninteractive flathub com.google.Chrome
fi
install_step Dropbox flatpak install --user --noninteractive flathub com.dropbox.Client
install_step Discord flatpak install --user --noninteractive flathub com.discordapp.Discord
install_step WordCraft install_craft_app wordcraft 0.18.1 7f3923f3537c020521318307428211d80848cd9ccb055265b23d6139216616a9
install_step GridCraft install_craft_app gridcraft 0.19.1 535289047c3891e5a238feaa186096ca3c0c283cdfde1e0fff72240f5f475d02

if (( ${#failed[@]} )); then
    printf '\nFailed steps:\n' >&2
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi
