#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -m) != x86_64 || ! -e /run/ostree-booted || $EUID == 0 ]]; then
    echo 'Run this as your regular user on installed x86_64 Fedora Kinoite.' >&2
    exit 1
fi

install_craft_app() {
    local ref="app/ai.storyteller.$1/x86_64/stable"
    local origin
    if origin=$(flatpak info --user --show-origin "$ref" 2>/dev/null); then
        if [[ $origin == artcraft-oci ]]; then
            return
        fi
        printf 'Switching %s from %s to ArtCraft.\n' "$1" "$origin"
        flatpak install --user --noninteractive --assumeyes --reinstall artcraft-oci "$ref"
        return
    fi
    flatpak install --user --noninteractive --assumeyes artcraft-oci "$ref"
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
install_step 'ArtCraft repository' flatpak remote-add --user --if-not-exists artcraft-oci https://getartcraft.com/artcraft-oci.flatpakrepo
install_step WordCraft install_craft_app wordcraft
install_step GridCraft install_craft_app gridcraft

if (( ${#failed[@]} )); then
    printf '\nFailed steps:\n' >&2
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi
