#!/usr/bin/env bash
# Parse the entire installer before running it when piped from curl.
{
set -euo pipefail

if [[ $(uname -m) != x86_64 || ! -e /run/ostree-booted || $EUID == 0 ]]; then
    echo 'Run this as your regular user on installed x86_64 Fedora Kinoite.' >&2
    exit 1
fi

echo 'Brother ADS-4100 scanner driver license: https://support.brother.com/g/s/agreement/English_lpr/agree.html'
read -r -p 'Type yes to accept the license and install the driver: ' answer </dev/tty
if [[ $answer != yes ]]; then
    exit 1
fi

workdir=$(mktemp -d)
trap 'rm -rf -- "$workdir"' EXIT
driver="$workdir/brscan5-1.7.0-0.x86_64.rpm"
curl --proto '=https' --proto-redir '=https' --fail --silent --show-error \
    --location --retry 3 --output "$driver" \
    https://download.brother.com/welcome/dlf104036/brscan5-1.7.0-0.x86_64.rpm
printf '%s  %s\n' 197f63a52e89b8744f5a3c2d843abb3b76d003d5d4830bdfe675c44841a6c72b "$driver" | sha256sum --check
sudo rpm-ostree install --idempotent --allow-inactive "$driver" sane-backends sane-backends-drivers-scanners skanpage

echo 'Reboot, then plug in and power on the ADS-4100 over USB.'
echo 'Run scanimage -L as your regular user, then open Skanpage for a test scan.'
}
