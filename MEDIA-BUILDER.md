# Fedora Kinoite office installer — experimental

The script `create-kinoite-media.sh` normally writes **two USB drives** on a **Linux** computer, or only the configuration USB with `--config-only`:

1. Official Fedora Kinoite 44 OSTree ISO (x86_64), verified against a downloaded SHA256 checksum manifest.
2. A FAT32 `OEMDRV` configuration drive containing Kickstart (`ks.cfg`), Wi-Fi profile and first-boot setup services.

It relies on Anaconda automatically detecting `/ks.cfg` on `OEMDRV`. This may behave differently across Kinoite ISO releases. **Not hardware-tested; test in a disposable UEFI VM with two USB devices/virtual drives before deployment.** Anaconda's installer interface and Fedora ISO layout may change. The ISO checksum manifest is downloaded via HTTPS but its GPG signature is *not* verified.

## Builder machine

Use Linux with root access and packages providing `curl`, `lsblk`, `sgdisk` (gdisk), `mkfs.vfat` (dosfstools), `openssl`, `partprobe`, `python3`, `dd`, `udevadm` and `sha256sum`.

Run:

```bash
sudo ./create-kinoite-media.sh
```

If you **already have a bootable Fedora Kinoite USB** and want to create **only** the configuration USB, run:

```bash
sudo ./create-kinoite-media.sh --config-only
```

Select only the configuration USB when prompted, verify its size/model in the displayed `lsblk` output, and type `ERASE-CONFIG` to confirm. **Only the selected configuration USB is wiped**. The existing bootable installer USB is not accessed or reformatted. ISO download and checksum verification are skipped in this mode.


Normal mode asks for **two USB devices**, while `--config-only` asks for **one**. Then enter the **Wi-Fi SSID and PSK** and the fixed administrator password for `buzag`. In the normal two-USB mode, both USB disks are destructively overwritten after `ERASE-BOTH` confirmation; in `--config-only` mode, only the configuration USB is wiped after `ERASE-CONFIG` confirmation. Verify the disk names carefully. An ISO is downloaded (several GiB) and verified; it is cached locally.

Optional override:

```bash
sudo NETBIRD_URL=https://netbird.a.h1v3.com ./create-kinoite-media.sh
```

If using a different Fedora ISO, set `FEDORA_VERSION`, `ISO_NAME`, `ISO_URL`, and `CHECKSUM_URL`. The builder is preconfigured for Fedora 44's verified published artifact, **not** for an unverified Fedora 45 ISO.

## Target computer

Connect both USB drives and boot the Fedora installer USB. If automatic `OEMDRV` detection works, the installer should ask (on TTY6) for the destination **internal disk**, the LUKS password (twice), secondary username and secondary account password (twice). It excludes disks identified by Linux as USB, requires typing `ERASE` before erasing the selected destination, and does not choose automatically. This filtering cannot protect against every storage topology: always verify the displayed drive.

Once Anaconda finishes, Fedora boots with `multi-user.target` while setup runs. Type the LUKS password at each restart. First boot: `rpm-ostree upgrade`, reboot. Second boot: fetch the current public `install-office.sh` and run it as the secondary user with `--unattended --netbird-url https://netbird.a.h1v3.com`; reboot once more after success. Third boot: graphical login is enabled. Setup state and log are in `/var/lib/kinoite-provision` and `/var/log/kinoite-provision.log`.

The target's secondary user is not permanently an admin. A `NOPASSWD` sudoers rule is installed only during the app setup phase and removed on completion or error. **The script fetched from GitHub is not pinned to a commit.** For production, pin a trusted Git commit and verify its SHA256. NetBird unattended setup configures its server and defers interactive enrollment; it does not automatically authenticate the user.

## Important limitations

- **Prototype, untested against an actual ISO.** Kickstart syntax or ISO layout could need adjustment. A USB configured this way is *not guaranteed* to be recognized with no boot arguments on every Kinoite live installer. The installer `%pre` interaction uses TTY6 and needs a local keyboard and monitor.
- Target needs internet access for updates and apps. The Wi-Fi profile supports WPA/WPA2 personal (`wpa-psk`), not enterprise Wi-Fi or some newer WPA3-only setups.
- **Secrets:** The Wi-Fi PSK and administrator hash are stored on the unencrypted `OEMDRV` USB. During installation, the newly entered LUKS passphrase temporarily appears in a generated Kickstart fragment in installer RAM, where privileged installer code could access it. Avoid booting untrusted media. LUKS unlocking is required at every boot.
- After script failure the setup phase retries on the next boot; check `/var/log/kinoite-provision.log`. Automatic retries of non-idempotent third-party app installers may need manual repair.
- Fedora Kinoite RPM layering in `install-office.sh` may stage another deployment requiring an additional reboot before NetBird can be launched.
- The ISO URL may become unavailable after a new Fedora release. Verify release availability on https://fedoraproject.org/atomic-desktops/kinoite/download/.

## Validation status

**Experimental — not ready for unattended production use.** This builder has been syntax-checked but not verified against an actual Kinoite ISO. `OEMDRV` automatic discovery and Kickstart support on the live installer must be validated in a disposable VM before use on a physical disk. If the live installer ignores `ks.cfg`, do **not** proceed with destructive manual installation.

For `--config-only`, match `FEDORA_VERSION` to the version of the existing bootable installer USB, because the generated OSTree ref depends on the Fedora version.
