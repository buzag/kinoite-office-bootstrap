#!/usr/bin/env bash
# Build Fedora Kinoite installation USB + automatic OEMDRV Kickstart USB.
# Linux builder only. Test first in a VM. Destructively writes the selected USB devices.
set -euo pipefail
umask 077

CONFIG_ONLY=false
case "${1:-}" in
    --config-only) CONFIG_ONLY=true; shift ;;
    --help|-h)
        echo 'Usage: sudo ./create-kinoite-media.sh [--config-only]'
        echo '  --config-only  Format/write only the OEMDRV configuration USB; keep an existing installer USB unchanged.'
        exit 0 ;;
    '') ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
esac
(( $# == 0 )) || { echo 'Unexpected extra arguments' >&2; exit 2; }

FEDORA_VERSION="${FEDORA_VERSION:-44}"
ISO_NAME="${ISO_NAME:-Fedora-Kinoite-ostree-x86_64-${FEDORA_VERSION}-1.7.iso}"
ISO_URL="${ISO_URL:-https://download.fedoraproject.org/pub/fedora/linux/releases/${FEDORA_VERSION}/Kinoite/x86_64/iso/${ISO_NAME}}"
CHECKSUM_URL="${CHECKSUM_URL:-https://download.fedoraproject.org/pub/fedora/linux/releases/${FEDORA_VERSION}/Kinoite/x86_64/iso/Fedora-Kinoite-${FEDORA_VERSION}-1.7-x86_64-CHECKSUM}"
NETBIRD_URL="${NETBIRD_URL:-https://netbird.a.h1v3.com}"
CACHE_DIR="${CACHE_DIR:-$PWD/fedora-cache}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ $(id -u) -eq 0 ]] || fail 'Run as root (sudo).'
[[ $(uname -s) == Linux ]] || fail 'Use a Linux builder machine.'
for cmd in lsblk findmnt udevadm curl sha256sum dd wipefs sgdisk partprobe mkfs.vfat openssl python3 mount umount readlink xargs awk sed; do
    command -v "$cmd" >/dev/null || fail "Missing command: $cmd"
done
[[ $NETBIRD_URL =~ ^https://[A-Za-z0-9.:-]+/?$ ]] || fail 'NETBIRD_URL must be an https:// hostname URL.'
if ! $CONFIG_ONLY; then mkdir -p "$CACHE_DIR"; fi

if ! $CONFIG_ONLY; then
    read -r -p 'Installer USB whole-disk device (example /dev/sdb): ' INSTALL_USB </dev/tty
    INSTALL_USB=$(readlink -f "$INSTALL_USB")
fi
read -r -p 'Kickstart USB whole-disk device (example /dev/sdc): ' CONFIG_USB </dev/tty
CONFIG_USB=$(readlink -f "$CONFIG_USB")
if ! $CONFIG_ONLY; then
    [[ $INSTALL_USB != "$CONFIG_USB" ]] || fail 'Choose two DIFFERENT USB drives.'
    devices=("$INSTALL_USB" "$CONFIG_USB")
else
    devices=("$CONFIG_USB")
fi
for dev in "${devices[@]}"; do
    [[ -b $dev && $(lsblk -dn -o TYPE "$dev") == disk ]] || fail "$dev is not a whole disk"
    [[ $(lsblk -dn -o TRAN "$dev" | xargs) == usb ]] || fail "$dev is not detected as USB; refusing to wipe"
    [[ -z $(lsblk -nr -o MOUNTPOINT "$dev" | grep -v '^$' || :) ]] || fail "Unmount all partitions on $dev first"
done
lsblk -o NAME,TRAN,SIZE,MODEL,TYPE "${devices[@]}"
if $CONFIG_ONLY; then
    echo 'ONLY THE CONFIGURATION USB WILL BE ERASED. The existing Fedora installer USB is not touched.'
    read -r -p 'Type ERASE-CONFIG to continue: ' confirm </dev/tty
    [[ $confirm == ERASE-CONFIG ]] || fail 'Cancelled.'
else
    echo 'BOTH SELECTED USB DEVICES WILL BE COMPLETELY ERASED.'
    read -r -p 'Type ERASE-BOTH to continue: ' confirm </dev/tty
    [[ $confirm == ERASE-BOTH ]] || fail 'Cancelled.'
fi

# Existing credentials are baked into configuration USB; prompt at BUILD time, not target installation.
read -r -p 'Wi-Fi SSID: ' WIFI_SSID </dev/tty
[[ -n $WIFI_SSID && $WIFI_SSID != *$'\n'* ]] || fail 'Invalid SSID'
read -rs -p 'Wi-Fi password: ' WIFI_PASSWORD </dev/tty; echo
[[ -n $WIFI_PASSWORD ]] || fail 'Wi-Fi password required'
read -rs -p 'Preconfigured buzag password: ' BUZAG_PASSWORD </dev/tty; echo
read -rs -p 'Confirm buzag password: ' BUZAG_CONFIRM </dev/tty; echo
[[ -n $BUZAG_PASSWORD && $BUZAG_PASSWORD == "$BUZAG_CONFIRM" ]] || fail 'buzag passwords differ or blank'
BUZAG_HASH=$(openssl passwd -6 -stdin <<<"$BUZAG_PASSWORD")
unset BUZAG_PASSWORD BUZAG_CONFIRM

if ! $CONFIG_ONLY; then
iso="$CACHE_DIR/$ISO_NAME"
checksum="$CACHE_DIR/$(basename "$CHECKSUM_URL")"
if [[ ! -s $iso ]]; then
    curl --fail --location --retry 3 -o "$iso.part" "$ISO_URL"
    mv -f "$iso.part" "$iso"
fi
curl --fail --location --retry 3 -o "$checksum" "$CHECKSUM_URL"
# Fedora's checksum file contains lines in the format: SHA256 (filename) = digest.
expected=$(sed -nE "s/^SHA256 \(${ISO_NAME//./\.}\) = ([[:xdigit:]]{64})$/\1/p" "$checksum" | head -n1)
[[ -n $expected ]] || fail 'Could not locate the ISO hash in Fedora checksum file.'
echo "$expected  $iso" | sha256sum -c - || fail 'ISO SHA256 verification failed'
echo 'ISO SHA256 verified against downloaded checksum file (GPG signature not verified).'

fi

work=$(mktemp -d)
trap '[[ -n ${mountdir:-} ]] && umount "$mountdir" 2>/dev/null || :; rm -rf "$work"' EXIT
mkdir "$work/content"

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
usb=/run/install/oemdrv
mkdir -p "$usb"
mounted=0
if ! mountpoint -q "$usb"; then
    mount -o ro /dev/disk/by-label/OEMDRV "$usb"
    mounted=1
fi
install -m 0700 "$usb/kinoite-provision.sh" /mnt/sysroot/usr/local/sbin/kinoite-provision
install -m 0600 "$usb/office-wifi.nmconnection" /mnt/sysroot/etc/NetworkManager/system-connections/office-wifi.nmconnection
install -m 0644 "$usb/kinoite-provision.service" /mnt/sysroot/etc/systemd/system/kinoite-provision.service
install -m 0600 /tmp/kinoite-secondary-user /mnt/sysroot/var/lib/kinoite-provision/secondary-user
mkdir -p /mnt/sysroot/etc/systemd/system/multi-user.target.wants
ln -sf ../kinoite-provision.service /mnt/sysroot/etc/systemd/system/multi-user.target.wants/kinoite-provision.service
ln -sf /usr/lib/systemd/system/multi-user.target /mnt/sysroot/etc/systemd/system/default.target
rm -f /mnt/sysroot/root/anaconda-ks.cfg /mnt/sysroot/root/original-ks.cfg
if (( mounted )); then umount "$usb"; fi
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

# FIRST write the official ISO to install USB, then prepare the OEMDRV USB.
if ! $CONFIG_ONLY; then
    echo "Writing official ISO to $INSTALL_USB ..."
    dd if="$iso" of="$INSTALL_USB" bs=8M status=progress conv=fsync
    sync
fi
echo "Formatting OEMDRV configuration drive $CONFIG_USB ..."
wipefs -a "$CONFIG_USB"
sgdisk --zap-all "$CONFIG_USB"
sgdisk -n 1:1MiB:0 -t 1:0700 "$CONFIG_USB"
partprobe "$CONFIG_USB"
udevadm settle
part=$(lsblk -nrpo NAME,TYPE "$CONFIG_USB" | awk '$2=="part"{print $1;exit}')
[[ -b $part ]] || fail 'Could not discover OEMDRV partition'
mkfs.vfat -F 32 -n OEMDRV "$part"
mountdir="$work/mnt"
mkdir "$mountdir"
mount "$part" "$mountdir"
cp -a "$work/content/." "$mountdir/"
sync
umount "$mountdir"
mountdir=''
if $CONFIG_ONLY; then
    echo 'Finished. Insert your EXISTING Fedora Kinoite boot USB alongside this OEMDRV USB.'
else
    echo "Finished. Insert BOTH USB drives and boot from $INSTALL_USB."
fi
echo 'The installer will attempt to discover OEMDRV/ks.cfg automatically (not tested against Kinoite live media).'
echo 'If your ISO does not detect OEMDRV, this media is NOT zero-parameter boot compatible; do not proceed with a destructive manual install.'
echo 'Expect disk, LUKS and secondary-user prompts. LUKS must be unlocked at each reboot.'
