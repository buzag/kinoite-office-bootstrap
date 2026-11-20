#!/usr/bin/env bash
# Generate a self-contained Fedora Kinoite Kickstart and Ventoy auto-install config.
# This script never formats USB drives and never downloads an ISO.
set -euo pipefail
umask 077

usage() {
  cat <<'HELP'
Usage: ./create-kinoite-media.sh [--output DIR] [--iso-name NAME] [--fedora-version N]
Generate only configuration files for a Ventoy USB. Does not require root.
ISO must be placed at /ISO/<NAME> on the Ventoy data partition.
HELP
}
OUTPUT_DIR="${OUTPUT_DIR:-$PWD/kinoite-ventoy-config}"
FEDORA_VERSION="${FEDORA_VERSION:-44}"
ISO_NAME="${ISO_NAME:-Fedora-Kinoite-ostree-x86_64-44-1.7.iso}"
NETBIRD_URL="${NETBIRD_URL:-https://netbird.a.h1v3.com}"
while (( $# )); do
  case "$1" in
    --output) (( $# >= 2 )) || { usage >&2; exit 2; }; OUTPUT_DIR=$2; shift 2 ;;
    --iso-name) (( $# >= 2 )) || { usage >&2; exit 2; }; ISO_NAME=$2; shift 2 ;;
    --fedora-version) (( $# >= 2 )) || { usage >&2; exit 2; }; FEDORA_VERSION=$2; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ $FEDORA_VERSION =~ ^[0-9]{2}$ ]] || { echo 'Invalid Fedora version' >&2; exit 2; }
[[ $ISO_NAME =~ ^[A-Za-z0-9._+-]+\.iso$ ]] || { echo 'ISO name must be a plain .iso filename' >&2; exit 2; }
[[ $NETBIRD_URL =~ ^https://[A-Za-z0-9.:-]+/?$ ]] || { echo 'Invalid NETBIRD_URL (HTTPS required)' >&2; exit 2; }
for cmd in python3 openssl base64; do command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }; done
[[ -t 0 ]] || { echo 'Run interactively in a terminal.' >&2; exit 1; }
[[ ! -e "$OUTPUT_DIR" || ! -e "$OUTPUT_DIR/ventoy" ]] || { echo "Refusing to overwrite existing ventoy configuration: $OUTPUT_DIR" >&2; exit 1; }
read -r -p 'Wi-Fi SSID: ' WIFI_SSID
read -rs -p 'Wi-Fi password: ' WIFI_PASSWORD; echo
read -rs -p 'Fixed buzag account password: ' BUZAG_PASSWORD; echo
read -rs -p 'Confirm buzag password: ' BUZAG_CONFIRM; echo
[[ -n $WIFI_SSID && -n $WIFI_PASSWORD && -n $BUZAG_PASSWORD && $BUZAG_PASSWORD == "$BUZAG_CONFIRM" ]] || { echo 'Missing credentials or mismatched passwords' >&2; exit 1; }
BUZAG_HASH=$(printf '%s\n' "$BUZAG_PASSWORD" | openssl passwd -6 -stdin)
unset BUZAG_PASSWORD BUZAG_CONFIRM
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/content"
# Kickstart %pre runs in installer RAM, prompts on virtual console 6, and emits a dynamic fragment.
cat > "$work/content/ks.cfg" <<'KS'
# Fedora Kinoite OSTree installer — tested configuration must be validated on your ISO before production use.
lang hu_HU.UTF-8
keyboard --vckeymap=hu --xlayouts='hu'
timezone Europe/Budapest --utc
selinux --enforcing
firstboot --disable
reboot
rootpw --lock
services --enabled=NetworkManager
ostreesetup --osname=fedora --remote=fedora --url=file:///ostree/repo --ref=FEDORA_REF --nogpg
user --name=buzag --groups=wheel --password=BUZAG_HASH --iscrypted
%include /tmp/kinoite-dynamic.ks

%pre --interpreter=/usr/bin/bash --log=/tmp/kinoite-pre.log
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
chvt 6 || :
exec 3<>/dev/tty6
printf '\033[2J\033[H' >&3
printf 'KINOITE INSTALL: disk selection and encryption\n' >&3
mapfile -t disks < <(lsblk -dn -p -o NAME,TYPE,TRAN,RM | awk '$2=="disk" && $3!="usb" && $4=="0" {print $1}')
((${#disks[@]})) || { echo 'No eligible non-USB disk detected' >&3; exit 1; }
for i in "${!disks[@]}"; do
    lsblk -dn -o NAME,SIZE,MODEL "${disks[$i]}" >&3
    printf '[%d] %s\n' "$((i+1))" "${disks[$i]}" >&3
done
printf 'Disk number to ERASE completely: ' >&3
IFS= read -r choice <&3
[[ $choice =~ ^[0-9]+$ && $choice -ge 1 && $choice -le ${#disks[@]} ]] || exit 1
dev=${disks[$((choice-1))]}
disk=${dev##*/}
printf 'Selected %s. Type ERASE to confirm: ' "$dev" >&3
IFS= read -r choice <&3
[[ $choice == ERASE ]] || exit 1
printf 'New disk encryption passphrase: ' >&3
stty -echo <&3
IFS= read -r luks <&3
printf '\nConfirm encryption passphrase: ' >&3
IFS= read -r luks2 <&3
stty echo <&3
printf '\n' >&3
[[ -n $luks && $luks == "$luks2" ]] || { echo 'Passphrases mismatch' >&3; exit 1; }
printf 'Secondary username (lowercase letters/digits/_/-): ' >&3
IFS= read -r secondary <&3
[[ $secondary =~ ^[a-z_][a-z0-9_-]{0,30}$ && $secondary != buzag ]] || exit 1
printf 'Secondary user password: ' >&3
stty -echo <&3
IFS= read -r pass <&3
printf '\nConfirm secondary user password: ' >&3
IFS= read -r pass2 <&3
stty echo <&3
printf '\n' >&3
[[ -n $pass && $pass == "$pass2" ]] || exit 1
passhash=$(printf '%s\n' "$pass" | openssl passwd -6 -stdin)
unset pass pass2
host="szekhely-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
# Kickstart quoting: secrets must not contain line breaks or double quotes.
[[ $luks != *'"'* && $luks != *$'\n'* && $luks != *'\\'* ]] || { echo 'Encryption password cannot contain double quotes or backslashes in this installer' >&3; exit 1; }
cat > /tmp/kinoite-dynamic.ks <<EOF
ignoredisk --only-use=$disk
clearpart --all --initlabel --drives=$disk
bootloader --boot-drive=$disk
autopart --type=btrfs --encrypted --luks-version=luks2 --passphrase="$luks"
network --hostname=$host
user --name=$secondary --password=$passhash --iscrypted
EOF
chmod 600 /tmp/kinoite-dynamic.ks
printf '%s\n' "$secondary" > /tmp/kinoite-secondary-user
printf 'Installing on %s as %s, hostname %s.\n' "$dev" "$secondary" "$host" >&3
printf 'Installation will continue. Switch to the Anaconda console for status.\n' >&3
exec 3>&-
chvt 1 || :
%end

%post --nochroot --interpreter=/usr/bin/bash --log=/mnt/sysroot/var/log/kinoite-provision-post.log
set -euo pipefail
mkdir -p /mnt/sysroot/usr/local/sbin /mnt/sysroot/etc/systemd/system /mnt/sysroot/etc/NetworkManager/system-connections /mnt/sysroot/var/lib/kinoite-provision
# All provisioning assets are embedded below (base64) in this Kickstart.
EMBEDDED_PAYLOADS
chmod 0700 /mnt/sysroot/usr/local/sbin/kinoite-provision
chmod 0600 /mnt/sysroot/etc/NetworkManager/system-connections/office-wifi.nmconnection
chmod 0644 /mnt/sysroot/etc/systemd/system/kinoite-provision.service
install -m 0600 /tmp/kinoite-secondary-user /mnt/sysroot/var/lib/kinoite-provision/secondary-user
mkdir -p /mnt/sysroot/etc/systemd/system/multi-user.target.wants
ln -sf ../kinoite-provision.service /mnt/sysroot/etc/systemd/system/multi-user.target.wants/kinoite-provision.service
ln -sf /usr/lib/systemd/system/multi-user.target /mnt/sysroot/etc/systemd/system/default.target
rm -f /mnt/sysroot/root/anaconda-ks.cfg /mnt/sysroot/root/original-ks.cfg
%end
KS

python3 - "$work/content/ks.cfg" "$FEDORA_VERSION" "$BUZAG_HASH" <<'PY'
from pathlib import Path
import sys
path=Path(sys.argv[1])
s=path.read_text().replace('FEDORA_REF', f'fedora/{sys.argv[2]}/x86_64/kinoite').replace('BUZAG_HASH',sys.argv[3]);path.write_text(s)
PY

cat > "$work/content/office-wifi.nmconnection" <<'CONN'
[connection]
id=Office Wi-Fi
uuid=00000000-0000-4000-8000-000000000001
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=WIFI_SSID_PLACEHOLDER

[wifi-security]
key-mgmt=wpa-psk
psk=WIFI_PASSWORD_PLACEHOLDER

[ipv4]
method=auto

[ipv6]
method=auto
CONN
KINOITE_WIFI_SSID="$WIFI_SSID" KINOITE_WIFI_PASSWORD="$WIFI_PASSWORD" python3 - "$work/content/office-wifi.nmconnection" <<'PY'
from pathlib import Path
import os,sys
p=Path(sys.argv[1]); s=p.read_text();
# Don't allow special INI tokens to inject another section.
for key, value in (('WIFI_SSID_PLACEHOLDER',os.environ['KINOITE_WIFI_SSID']),('WIFI_PASSWORD_PLACEHOLDER',os.environ['KINOITE_WIFI_PASSWORD'])):
 if '\n' in value or '\r' in value or '\\' in value: raise SystemExit('Wi-Fi values cannot contain line breaks or backslashes for this media builder')
 s=s.replace(key,value)
p.write_text(s)
PY

cat > "$work/content/kinoite-provision.service" <<'UNIT'
[Unit]
Description=Kinoite one-time OS update and user application setup
Wants=network-online.target
After=NetworkManager.service network-online.target
ConditionPathExists=!/var/lib/kinoite-provision/done

[Service]
Type=oneshot
TimeoutStartSec=infinity
ExecStart=/usr/local/sbin/kinoite-provision

[Install]
WantedBy=multi-user.target
UNIT

cat > "$work/content/kinoite-provision.sh" <<'PROVISION'
#!/usr/bin/env bash
set -euo pipefail
umask 077
state=/var/lib/kinoite-provision
mkdir -p "$state"
exec > >(tee -a /var/log/kinoite-provision.log) 2>&1
phase=$(cat "$state/phase" 2>/dev/null || echo update)
wait_network() {
    for _ in {1..60}; do
        if curl --connect-timeout 5 --max-time 10 -fsSI https://raw.githubusercontent.com >/dev/null; then return; fi
        sleep 10
    done
    echo 'No working network; setup will retry on next boot' >&2
    exit 1
}
if [[ $phase == update ]]; then
    wait_network
    rpm-ostree upgrade
    echo apps > "$state/phase"
    systemctl reboot
    exit 0
fi
if [[ $phase == apps ]]; then
    wait_network
    username=$(cat "$state/secondary-user")
    id "$username" >/dev/null
    uid=$(id -u "$username")
    # Setup-only sudo access; never leave this privilege behind after a successful run.
    printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$username" > /etc/sudoers.d/90-kinoite-provision
    chmod 0440 /etc/sudoers.d/90-kinoite-provision
    cleanup_setup() {
        rm -f /etc/sudoers.d/90-kinoite-provision
        loginctl disable-linger "$username" || :
    }
    trap cleanup_setup EXIT
    if ! runuser -u "$username" -- /usr/bin/sudo -n /usr/bin/true; then
        echo "Temporary sudo authorization failed for $username. Check /etc/sudoers and its included rules." >&2
        exit 1
    fi
    loginctl enable-linger "$username"
    systemctl start "user@${uid}.service"
    mkdir -p "/run/user/$uid"
    url='NETBIRD_URL_PLACEHOLDER'
    # Curl script is executed in the secondary user's own account, not root.
    curl -fsSL --retry 3 'https://raw.githubusercontent.com/buzag/kinoite-office-bootstrap/refs/heads/main/install-office.sh' -o "$state/install-office.sh"
    runuser -u "$username" -- env HOME="$(getent passwd "$username" | cut -d: -f6)" \
        USER="$username" LOGNAME="$username" XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        /usr/bin/bash -s -- --unattended --netbird-url "$url" < "$state/install-office.sh"
    cleanup_setup
    trap - EXIT
    rm -f "$state/install-office.sh"
    echo done > "$state/phase"
    touch "$state/done"
    systemctl disable kinoite-provision.service || :
    systemctl set-default graphical.target
    systemctl reboot
    exit 0
fi
echo "Unknown phase: $phase" >&2
exit 1
PROVISION
python3 - "$work/content/kinoite-provision.sh" "$NETBIRD_URL" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); p.write_text(p.read_text().replace('NETBIRD_URL_PLACEHOLDER',sys.argv[2]))
PY


# Make kickstart self-contained: Ventoy only injects the template itself.
# Base64 is transport encoding, not encryption; treat the resulting USB as sensitive.
KINOITE_WORK="$work" python3 - <<'PYEMBED'
import base64, os
from pathlib import Path
w=Path(os.environ['KINOITE_WORK'])
ks=w/'content/ks.cfg'
s=ks.read_text()
blocks=[]
for name, dest in [
 ('kinoite-provision.sh','/mnt/sysroot/usr/local/sbin/kinoite-provision'),
 ('office-wifi.nmconnection','/mnt/sysroot/etc/NetworkManager/system-connections/office-wifi.nmconnection'),
 ('kinoite-provision.service','/mnt/sysroot/etc/systemd/system/kinoite-provision.service')]:
   data=base64.b64encode((w/'content'/name).read_bytes()).decode('ascii')
   blocks.append("base64 -d > '"+dest+"' <<'PAYLOAD'\n"+"\n".join(data[i:i+76] for i in range(0,len(data),76))+"\nPAYLOAD")
assert s.count('EMBEDDED_PAYLOADS')==1
ks.write_text(s.replace('EMBEDDED_PAYLOADS','\n'.join(blocks)))
PYEMBED
mkdir -p "$work/out/ventoy/script" "$work/out/ISO"
mv "$work/content/ks.cfg" "$work/out/ventoy/script/kinoite.ks"
python3 - "$work/out/ventoy/ventoy.json" "$ISO_NAME" <<'PYJSON'
import json,sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({"auto_install":[{
  "image":"/ISO/"+sys.argv[2],
  "template":"/ventoy/script/kinoite.ks",
  "autosel":1
}]},indent=2)+"\n")
PYJSON
cat > "$work/out/ISO/PUT-FEDORA-ISO-HERE.txt" <<EOF
Copy the official Fedora Kinoite ISO here with this EXACT filename:
$ISO_NAME
Do not rename it unless you regenerate ventoy.json accordingly.
EOF
cat > "$work/out/README.txt" <<EOF
Configuration only. No USB formatting has occurred.
1. Use the Codex or Claude prompt in the repository’s MEDIA-BUILDER.md to prepare the USB.
2. Set the Ventoy data partition filesystem label to KINOITE (NOT the EFI/VTOYEFI partition).
3. Copy the official verified $ISO_NAME to /ISO/ on the Ventoy data partition.
4. Copy ventoy/ directory and its contents to the root of the Ventoy data partition.
5. Validate ventoy/ventoy.json and boot-test in a disposable UEFI VM before use.
WARNING: Wi-Fi password is embedded in ventoy/script/kinoite.ks; protect the USB.
WARNING: Kinoite + Ventoy Kickstart compatibility and interactive %pre still require testing.
EOF
mkdir -p "$OUTPUT_DIR"
cp -a "$work/out/." "$OUTPUT_DIR/"
chmod 0700 "$OUTPUT_DIR" "$OUTPUT_DIR/ventoy" "$OUTPUT_DIR/ventoy/script"
chmod 0600 "$OUTPUT_DIR/ventoy/script/kinoite.ks" "$OUTPUT_DIR/ventoy/ventoy.json"
echo "Created Ventoy config ONLY at: $OUTPUT_DIR"
echo "Expected ISO at /ISO/$ISO_NAME and volume label KINOITE"
echo 'No USB was modified. LUKS passphrase will be requested at each boot.'
echo 'EXPERIMENTAL: verify in a disposable VM before disk erasure.'
