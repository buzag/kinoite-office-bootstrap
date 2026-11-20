#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -m) != x86_64 || ! -e /run/ostree-booted || $EUID == 0 ]]; then
    echo 'Run this as your regular user on installed x86_64 Fedora Kinoite.' >&2
    exit 1
fi
if [[ -z ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
    echo 'Open a terminal in your desktop session to launch the ÁNYK installer.' >&2
    exit 1
fi

java_root="${XDG_DATA_HOME:-$HOME/.local/share}/kinoite-anyk"
java_home="$java_root/temurin-8u514-b01"
mkdir -p "$java_root"
workdir=$(mktemp -d "$java_root/.install.XXXXXXXX")
trap 'rm -rf -- "$workdir"' EXIT

download() {
    curl --proto '=https' --proto-redir '=https' --fail --silent --show-error \
        --location --retry 3 --output "$2" "$1"
}

if [[ ! -x "$java_home/bin/java" ]]; then
    archive="$workdir/temurin.tar.gz"
    download 'https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u514-b01/OpenJDK8U-jre_x64_linux_hotspot_8u514b01.tar.gz' "$archive"
    printf '%s  %s\n' b3e38dc60261a548fe83d297bf6faf7880f1b84f7d48e5741f3c6f3c3021cd4d "$archive" | sha256sum --check
    mkdir "$workdir/java"
    tar -xzf "$archive" --strip-components=1 -C "$workdir/java"
    "$workdir/java/bin/java" -version
    mv -T "$workdir/java" "$java_home"
fi

download 'https://nav.gov.hu/pfile/programFile?path=/nyomtatvanyok/letoltesek/nyomtatvanykitolto_programok/nyomtatvany_apeh/keretprogramok/AbevJava' "$workdir/abevjava_install.jar"
destination="$HOME/abevjava"
echo "Set the installation directory to $destination, then complete NAV's setup."
JAVA_HOME="$java_home" PATH="$java_home/bin:$PATH" "$java_home/bin/java" -jar "$workdir/abevjava_install.jar"

if [[ ! -f "$destination/abevjava_start" || ! -f "$destination/setenv" ]]; then
    echo "The NAV launcher was not found in $destination. Check the installer's selected directory." >&2
    exit 1
fi

# NAV's launcher sources setenv and prepends JAVA_HOME_ABEV to its java command.
if ! grep -q '^JAVA_HOME_ABEV=' "$destination/setenv"; then
    printf '\n%s\n' 'JAVA_HOME_ABEV="${XDG_DATA_HOME:-$HOME/.local/share}/kinoite-anyk/temurin-8u514-b01/bin/"' >> "$destination/setenv"
fi
echo "Open ÁNYK from its installed shortcut, or run: cd \"$destination\" && ./abevjava_start"
