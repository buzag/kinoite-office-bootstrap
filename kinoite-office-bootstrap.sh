#!/usr/bin/env bash
# Kinoite office trial bootstrapper
#
# Run only on an INSTALLED Fedora Kinoite system (not from a live USB).
# It stages one new rpm-ostree deployment, then installs the two office apps
# as per-user Flatpaks. Reboot once when it finishes.

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly NETBIRD_REPO_URL="https://pkgs.netbird.io/yum/"
readonly NETBIRD_GPG_KEY="https://pkgs.netbird.io/yum/repodata/repomd.xml.key"
readonly CHROME_RPM_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm"
readonly DROPBOX_RPM_URL="https://linux.dropboxstatic.com/packages/fedora/dropbox-latest.x86_64.rpm"

# Set both variables in your GitHub copy before publishing it. Obtain them from
# the Brother ADS-4100 Linux (rpm) download page. Do not use an unverified URL.
BROTHER_RPM_URL="https://download.brother.com/welcome/dlf104036/brscan5-1.8.1-0.x86_64.rpm"
BROTHER_RPM_SHA256="a085e529e2193f050f489639c70e19f52afdec7252b2ac5240eaaddec4febdf7"


die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }

usage() {
  cat <<'EOF'
Usage: kinoite-office-bootstrap.sh [--brother-rpm URL_OR_PATH] [--brother-sha256 SHA256]

The Brother driver is deliberately checksum-pinned. Either set
BROTHER_RPM_URL and BROTHER_RPM_SHA256 at the top of this script before
publishing, or pass both values here.
EOF
}

while (($#)); do
  case "$1" in
    --brother-rpm) BROTHER_RPM_URL=${2:?"--brother-rpm needs a URL or path"}; shift 2 ;;
    --brother-sha256) BROTHER_RPM_SHA256=${2:?"--brother-sha256 needs a value"}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ $(id -u) -ne 0 ]] || die "Run this as the normal Kinoite user, not as root."
[[ $(uname -m) == x86_64 ]] || die "This setup currently targets an x86_64 PC."
command -v rpm-ostree >/dev/null || die "This is not an rpm-ostree system (Kinoite is required)."
[[ -e /run/ostree-booted ]] || die "Boot into an installed Kinoite deployment first; do not run this from a live USB."
command -v flatpak >/dev/null || die "flatpak is missing from this Kinoite installation."
command -v curl >/dev/null || die "curl is required."
command -v python3 >/dev/null || die "python3 is required."
command -v sha256sum >/dev/null || die "sha256sum is required."

[[ -n "$BROTHER_RPM_URL" ]] || die "Set BROTHER_RPM_URL to the official ADS-4100 64-bit RPM URL."
[[ "$BROTHER_RPM_SHA256" =~ ^[[:xdigit:]]{64}$ ]] || die "Set BROTHER_RPM_SHA256 to the 64-character SHA-256 of that RPM."

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

download() {
  local source=$1 destination=$2
  if [[ -f "$source" ]]; then
    cp -- "$source" "$destination"
  else
    curl --fail --location --proto '=https' --tlsv1.2 --output "$destination" "$source"
  fi
}

github_flatpak() {
  local repository=$1 output=$2 api_json metadata url expected_sha
  api_json="$workdir/${repository//\//_}.json"
  curl --fail --location --proto '=https' --tlsv1.2 \
    --header 'Accept: application/vnd.github+json' \
    --output "$api_json" "https://api.github.com/repos/${repository}/releases/latest"
  metadata=$(python3 - "$api_json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as file:
    assets = json.load(file).get("assets", [])
matches = [a for a in assets
           if a.get("name", "").endswith("-linux-x86_64.flatpak")]
if len(matches) != 1:
    raise SystemExit("Expected exactly one x86_64 Flatpak asset; found " + str(len(matches)))
asset = matches[0]
digest = asset.get("digest", "")
if not digest.startswith("sha256:") or len(digest) != 71:
    raise SystemExit("Release asset has no SHA-256 digest")
print(asset["browser_download_url"], digest.removeprefix("sha256:"))
PY
  ) || die "Could not find a checksum-published x86_64 Flatpak release for $repository."
  read -r url expected_sha <<<"$metadata"
  [[ -n "$url" && "$expected_sha" =~ ^[[:xdigit:]]{64}$ ]] \
    || die "Invalid release metadata for $repository."
  download "$url" "$output"
  printf '%s  %s\n' "$expected_sha" "$output" | sha256sum --check --status \
    || die "Checksum does not match for the $repository Flatpak."
}

download "https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.x86_64.rpm" "$workdir/chatgpt.x86_64.rpm"

note "Downloading vendor packages"
download "$CHROME_RPM_URL" "$workdir/google-chrome.rpm"
download "$DROPBOX_RPM_URL" "$workdir/dropbox.rpm"
download "$BROTHER_RPM_URL" "$workdir/brother-ads-4100.rpm"
printf '%s  %s\n' "$BROTHER_RPM_SHA256" "$workdir/brother-ads-4100.rpm" | sha256sum --check --status \
  || die "Brother RPM checksum does not match; no system changes were made."

note "Downloading WordCraft and GridCraft Flatpaks"
github_flatpak "storytold/wordcraft" "$workdir/wordcraft.flatpak"
github_flatpak "storytold/gridcraft" "$workdir/gridcraft.flatpak"

github_flatpak "storytold/craft-launcher" "$workdir/artcraft-launcher.flatpak"

note "Adding the official NetBird package source"
sudo install -d -m 0755 /etc/yum.repos.d
printf '%s\n' \
  '[netbird]' \
  'name=NetBird Repository' \
  "baseurl=$NETBIRD_REPO_URL" \
  'enabled=1' \
  'gpgcheck=1' \
  "gpgkey=$NETBIRD_GPG_KEY" \
  'repo_gpgcheck=1' | sudo tee /etc/yum.repos.d/netbird.repo >/dev/null

note "Staging the immutable system deployment"
sudo rpm-ostree install \
  "$workdir/chatgpt.x86_64.rpm" \
  netbird \
  sane-backends \
  sane-backends-drivers-scanners \
  sane-airscan \
  "$workdir/google-chrome.rpm" \
  "$workdir/dropbox.rpm" \
  "$workdir/brother-ads-4100.rpm"

note "Installing the office applications for $USER"
flatpak install --user --noninteractive --bundle "$workdir/wordcraft.flatpak"
flatpak install --user --noninteractive --bundle "$workdir/gridcraft.flatpak"

flatpak install --user --noninteractive --bundle "$workdir/artcraft-launcher.flatpak"

cat <<'EOF'

Open ArtCraft Launcher to update WordCraft and GridCraft.
After reboot, open ChatGPT and sign in to use Codex.
ChatGPT Linux preview on Kinoite 45 needs compatibility testing.

Finished. Reboot now to enter the new Kinoite deployment:

  systemctl reboot

After reboot, complete these interactive steps (credentials are intentionally
not stored in this script):

  1. Open Chrome, Dropbox, WordCraft, and GridCraft from the application menu.
  2. Sign in to Dropbox and choose a folder on the Kinoite filesystem.
  3. Run: sudo systemctl enable --now netbird
     Then authenticate with: netbird up
  4. Connect the ADS-4100, then test discovery with: scanimage -L
     For a network scanner, first try: airscan-discover

Do not use a reusable NetBird setup key or Dropbox credentials in this script.
EOF
