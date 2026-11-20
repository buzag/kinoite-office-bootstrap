#!/usr/bin/env bash
# Parse the entire installer before running it when piped from curl.
{
set -euo pipefail

if [[ $(uname -m) != x86_64 || ! -e /run/ostree-booted || $EUID == 0 ]]; then
    echo 'Run this as your regular user on installed x86_64 Fedora Kinoite.' >&2
    exit 1
fi

download() {
    curl --proto '=https' --proto-redir '=https' --fail --silent --show-error \
        --location --retry 3 --output "$2" "$1"
}

install_anyk() (
    destination="$HOME/abevjava"
    if [[ -f "$destination/abevjava_start" && -f "$destination/setenv" ]]; then
        echo "ÁNYK is already installed in $destination."
        exit 0
    fi

    if [[ -z ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
        echo 'Open a terminal in your desktop session to launch the ÁNYK installer.' >&2
        exit 1
    fi

    java_root="${XDG_DATA_HOME:-$HOME/.local/share}/kinoite-anyk"
    java_home="$java_root/temurin-8u514-b01"
    mkdir -p "$java_root" || exit 1
    workdir=$(mktemp -d "$java_root/.install.XXXXXXXX") || exit 1
    trap 'rm -rf -- "$workdir"' EXIT

    if [[ ! -x "$java_home/bin/java" ]]; then
        archive="$workdir/temurin.tar.gz"
        download 'https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u514-b01/OpenJDK8U-jre_x64_linux_hotspot_8u514b01.tar.gz' "$archive" || exit 1
        printf '%s  %s\n' b3e38dc60261a548fe83d297bf6faf7880f1b84f7d48e5741f3c6f3c3021cd4d "$archive" | sha256sum --check || exit 1
        mkdir "$workdir/java" || exit 1
        tar -xzf "$archive" --strip-components=1 -C "$workdir/java" || exit 1
        "$workdir/java/bin/java" -version || exit 1
        mv -T "$workdir/java" "$java_home" || exit 1
    fi

    download 'https://nav.gov.hu/pfile/programFile?path=/nyomtatvanyok/letoltesek/nyomtatvanykitolto_programok/nyomtatvany_apeh/keretprogramok/AbevJava' "$workdir/abevjava_install.jar" || exit 1
    echo "Set the installation directory to $destination, then complete NAV's setup."
    JAVA_HOME="$java_home" PATH="$java_home/bin:$PATH" "$java_home/bin/java" -jar "$workdir/abevjava_install.jar" || exit 1

    if [[ ! -f "$destination/abevjava_start" || ! -f "$destination/setenv" ]]; then
        echo "The NAV launcher was not found in $destination. Check the installer's selected directory." >&2
        exit 1
    fi

    # NAV's launcher sources setenv and prepends JAVA_HOME_ABEV to its java command.
    if ! grep -q '^JAVA_HOME_ABEV=' "$destination/setenv"; then
        printf '\n%s\n' 'JAVA_HOME_ABEV="${XDG_DATA_HOME:-$HOME/.local/share}/kinoite-anyk/temurin-8u514-b01/bin/"' >> "$destination/setenv" || exit 1
    fi
    echo "Open ÁNYK from its installed shortcut, or run: cd \"$destination\" && ./abevjava_start"
)

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

install_chatgpt() {
    local key=/etc/pki/rpm-gpg/RPM-GPG-KEY-chatgpt-3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4.asc

    # Same public signing key and repository shipped in OpenAI's Fedora RPM.
    if [[ ! -e "$key" ]]; then
        sudo install -d -m 0755 /etc/pki/rpm-gpg || return
        sudo tee "$key" >/dev/null <<'KEY' || return
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGpypFUBEACi1Vvzq9pIpA6lj7chbqELuxJtVuzUzxrasa6ZU0yF4yhq7jf8
3YkJRHwbezBKeQyzJ5lkX0EhXS8aXxUhMAm3PFpAlwcInfKzmV7atJwvaxIw6Rmd
GYe9fBWKjTN/SmPIjtyxrTznZY97+TfD1AeGZpLaJ8fsnhrC+HkiN2TACiTocgpe
hFiP0OWK7mWZeTWnY2scpIYXP1Ro7nQv4KacmY4JacTQ7m/HM0Qej/3olhuEv2Cw
lMVWw57/oHhmTllfLDQOogFQyIVqaaR98y/Eu6cAabSfcsqAAZ2A8vfHYD27z28J
vLO2PZEJd5ThlnX4Zqv0eIpZdBj//8Sl/MSqTshFZ1NDsRoqwdqw284X5MpnOJ4k
4Sc2Se8tJxt/nCeibH3dJ504Fb1X/mnOqhCAQ6pVJz4RB5HRlFPSkxVPyag1v1m/
7T4vie+OR4eqFQNz6mudrOoMmeVIfyL5fbe4cOr4fk/FyvEE2xMgkFatPqXn7vM9
og+zremPCfwRAFpBPyX74VowFY7llcdaj/w8K5T8PzM14Hb3E4ZKizMluKmTvTq9
WE1/eSQJLLQqXD5VmtmdUaC/VyE/1ZlIxcA1LWqvEQ327UXREvX/nHsrkKrl956W
jzkiHFUTsD1NJ0dMfs+csOt8Furb5jZj+HsMmCm9jLdfz5b/4WKLPbvxIwARAQAB
tBZDb2RleCBMaW51eCBSZXBvc2l0b3J5iQJRBBMBCgA7FiEEO/oOSui4zBai2bpo
SjtKVmxGYOQFAmpypFUCGwMFCwkIBwICIgIGFQoJCAsCBBYCAwECHgcCF4AACgkQ
SjtKVmxGYORlCQ/9FyikZo8HQcJBP9E/oXVPds/fQnIFB2qJR2z3DrfYEonNt/ev
SAySkPPq4/mEOjaI0pFlDDGSaps+FTcJFgoVRTasBIF7JJivvjW9ap8iWEbhhVLe
IrFLbMLpUcTRntUx7R4fVMJ/1/cGn+NWZmNwS9ORorzSyCH0IAgCw1Xc3ZrjuMbF
VjdToMC1TiXXCEmlYpQakmQ3Ay1cH0FHC2BBNn1MNVkJdPhpZIZCdhaMPHfYFpyo
pg8wFvZ5iIcvlbMgyuy8CPJVRWUcYy2dOhEOGnYJnXRPkE3E1hf8YOHNzRlduH89
6lT9qcEK2+fpLfrVGoc4zscLZ+Ey+Ko6iQRdVE1j67+wNR3hX8ukue574v1N/xxu
i575jumSE19lEj1sH4+P4gFHOtTbF0JhKKzLctbga0IAwTPKhnt3qzj1U5Yj/MZS
uEVjrLhdRauOuFBXUclgyVf2w/lE85UUOdlcollsYA6Huq7xDamqf8SslZQGre3E
I+lhpqJR1cOwDMUzzcl40uTyhrxXXd/bk4QSlhZbwHR25Pnt+ZMtWavlQWS0eDEV
8djuXAURCmx5WOqAFB/TJe1mn5EvyWg4VFzrY/NVNOpzgY5+Xp7J28z7f637r712
Eu9j4imVcdPigwS+jf/0f81i2o9b82Y26TN8+EtDLCY841MJ1lrjDrX/dno=
=Y+3h
-----END PGP PUBLIC KEY BLOCK-----
KEY
    fi
    if [[ ! -e /etc/yum.repos.d/chatgpt.repo ]]; then
        sudo tee /etc/yum.repos.d/chatgpt.repo >/dev/null <<'REPO' || return
[openai-chatgpt]
name=ChatGPT
baseurl=https://persistent.oaistatic.com/codex-app-prod/linux/rpm/$basearch
enabled=1
type=rpm-md
gpgcheck=1
repo_gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-chatgpt-3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4.asc
REPO
    fi
    sudo rpm-ostree install --idempotent --allow-inactive chatgpt || return
    echo 'If ChatGPT was newly staged, reboot and open ChatGPT from the application menu. Select Codex after signing in.'
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
install_step 'ChatGPT desktop with Codex' install_chatgpt

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

install_step ÁNYK install_anyk

if (( ${#failed[@]} )); then
    printf '\nFailed steps:\n' >&2
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi
}
