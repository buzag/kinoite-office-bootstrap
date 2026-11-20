# Fedora Kinoite — Ventoy unattended installation (experimental)

This directory contains **a configuration-only generator**, `create-kinoite-media.sh`. It **does not download an ISO, partition a disk, format a USB, or install Ventoy**. Run the generator on Linux to create a self-contained Kickstart template and Ventoy's `auto_install` mapping; use the prompt below with Codex or Claude to create the USB from the generated files.

## 1. Generate the config (Linux)

```bash
bash create-kinoite-media.sh --output ./kinoite-ventoy-config \
  --iso-name Fedora-Kinoite-ostree-x86_64-44-1.7.iso \
  --fedora-version 44
```

The generator asks for Wi-Fi SSID/password and the fixed `buzag` account password. **Never commit the generated configuration or copy it to a public location**. The generated Kickstart holds a reversible copy of the Wi-Fi password; the account password is stored as a salted hash. The secondary user credentials and the LUKS passphrase are requested only *on the destination computer* during installation. You will need to unlock LUKS for each reboot.

Output structure:

```text
kinoite-ventoy-config/
├── README.txt
├── ISO/
│   └── PUT-FEDORA-ISO-HERE.txt
└── ventoy/
    ├── ventoy.json
    └── script/
        └── kinoite.ks
```

The final Ventoy USB must contain `/ISO/<exact-iso-filename>`, `/ventoy/ventoy.json` and `/ventoy/script/kinoite.ks` on its **large data partition**. Label that data partition `KINOITE`, not the small Ventoy EFI partition. `ventoy.json` points to an exact filename; update/re-generate the config if that filename changes. Use the Fedora version corresponding to the ISO. NetBird management URL defaults to `https://netbird.a.h1v3.com`; override with `NETBIRD_URL=https://...` when running the generator.

## 2. Copy-paste prompt for Codex or Claude

Copy the entire block into Codex or Claude on the Linux machine connected to the USB drive.

```text
Prepare one Fedora Kinoite Ventoy installer USB on this Linux computer.

1. The source repo is https://github.com/buzag/kinoite-office-bootstrap.git. Use its existing checkout if available, or clone it into a new local directory. Find create-kinoite-media.sh in the repo root.
2. Check for ventoy/ventoy.json and ventoy/script/kinoite.ks under kinoite-ventoy-config in the repo checkout and in my working directory. If I provided a different config directory, use that. If the configuration is missing, have me run this in my own terminal using the actual repo path:
   bash /absolute/path/to/kinoite-office-bootstrap/create-kinoite-media.sh --output /absolute/path/to/kinoite-ventoy-config
   Give me the real paths and wait until I finish. I enter the Wi-Fi and buzag passwords directly into the generator. Do not ask me to paste passwords or the generated Kickstart into chat.
3. Read the ISO filename from ventoy.json. Find or download that exact ISO from Fedora and verify its SHA-256 against the official CHECKSUM file. Verify that file's GPG signature if possible. If the exact ISO is unavailable, stop and tell me which filename is needed.
4. List the block devices with path, model, size, and transport. Ask me to choose the USB disk and explicitly confirm its erasure before installing the official Ventoy release. Never infer the target disk or erase an internal disk.
5. Label the large Ventoy data partition KINOITE and leave the small EFI partition alone. Copy the verified ISO to /ISO/ and the generated ventoy directory to the root of the data partition. Verify the copied ISO, ventoy.json mapping, and Kickstart file, then safely unmount the USB.
6. Report what you verified. Treat Kickstart boot compatibility as untested unless the Kickstart actually ran in a disposable UEFI VM.
```

## 3. Intended target installation flow

1. Boot the Ventoy drive and select the Kinoite ISO. The `auto_install` plugin should provide `kinoite.ks` automatically (configured with `autosel: 1`).
2. In Kickstart `%pre`, choose the **internal destination disk**, confirm complete erasure, enter and confirm a LUKS passphrase, and enter a secondary username/password.
3. Install Fedora Kinoite with Hungarian language/keyboard, Budapest timezone, `buzag` and the secondary account, and a random `szekhely-...` hostname.
4. On the installed system, upgrade `rpm-ostree`, then reboot (enter LUKS passphrase).
5. Run the existing `install-office.sh --unattended --netbird-url https://netbird.a.h1v3.com` as the secondary user with temporary noninteractive sudo access, reboot again (enter LUKS passphrase), and present the graphical login screen. NetBird interactive authorization remains deferred.

## Important limitations

**This is an experimental prototype, NOT a tested unattended installation medium.** Ventoy supports Fedora Kickstart templates in principle, but that does not establish compatibility with the exact Kinoite OSTree ISO or its live installer. The custom Kickstart `%pre` prompt uses `/dev/tty6`; this and the OSTree `%post` operations must be validated with the actual ISO. The test must show that the Kickstart **really ran** — simply reaching the normal Anaconda installer does not count. Test only in a disposable UEFI VM until validated. The current `%post` and first-boot systemd service may need adjustment for your chosen Fedora version.

The generated Kickstart uses an embedded base64 payload for setup scripts and Wi-Fi settings. Base64 is **not encryption**. Generated files should be kept private and deleted from the builder computer when no longer needed. The builder does not ask for or retain the secondary user's or LUKS passwords.

Ventoy official documentation: https://ventoy.net/en/plugin_autoinstall.html
