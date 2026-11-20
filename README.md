# Fedora Kinoite office setup

On an installed **64-bit Intel or AMD Fedora Kinoite** desktop, open Konsole as your regular user and copy the line for the setup you want. Each installer runs independently. The office and scanner installers ask for administrator access and need a reboot to activate system packages.

## Office apps

Installs NetBird, WordCraft, GridCraft, Google Chrome, Dropbox, and Discord.

```bash
( f=$(mktemp) && trap 'rm -f -- "$f"' EXIT && curl --proto '=https' --proto-redir '=https' -fsSL 'https://raw.githubusercontent.com/buzag/kinoite-office-bootstrap/main/install-office.sh' -o "$f" && bash "$f" )
```

After reboot, run `sudo systemctl enable --now netbird`, then `netbird up` to sign in. For a self-hosted setup, use `netbird up --management-url https://YOUR-NETBIRD-SERVER`. Open Dropbox and Discord from the application menu to sign in.

NetBird installs first from its signed RPM repository. Chrome, Dropbox, and Discord are installed per user from Flathub. An existing Chrome installation is reused. WordCraft and GridCraft use checksum-pinned upstream Flatpak bundles.

If a step fails, the installer attempts the rest and lists failed steps at the end. You can rerun the same command. NetBird is installed as a system service with a command-line client. After reboot, use `netbird version` to check that it is available.

## ÁNYK (AbevJava)

```bash
( f=$(mktemp) && trap 'rm -f -- "$f"' EXIT && curl --proto '=https' --proto-redir '=https' -fsSL 'https://raw.githubusercontent.com/buzag/kinoite-office-bootstrap/main/install-anyk.sh' -o "$f" && bash "$f" )
```

The script downloads the official NAV installer and opens its setup window with a per-user Temurin Java 8 runtime. Set the installation directory to `$HOME/abevjava` (the script prints the full path) and select **Felhasználói beállítások elvégzése** in the setup options. Launch ÁNYK from its shortcut or run `cd "$HOME/abevjava" && ./abevjava_start`. No reboot is needed. See the [NAV Linux installation guide](https://nav.gov.hu/pfile/file?path=%2Fnyomtatvanyok%2Fletoltesek%2Fnyomtatvanykitolto_programok%2Fnyomtatvany_apeh%2Fkeretprogramok%2Fld_abevjava%2Ftelepitesi-leiras-linux-2021.10.21).

## Brother ADS-4100 scanner

```bash
( f=$(mktemp) && trap 'rm -f -- "$f"' EXIT && curl --proto '=https' --proto-redir '=https' -fsSL 'https://raw.githubusercontent.com/buzag/kinoite-office-bootstrap/main/install-scanner.sh' -o "$f" && bash "$f" )
```

Review the [Brother driver license](https://support.brother.com/g/s/agreement/English_lpr/agree.html) before accepting it in the terminal. The installer layers Brother's `brscan5` RPM, SANE tools, and Skanpage. After reboot, connect and power on the scanner over USB, run `scanimage -L`, then test a multi-page scan in Skanpage.
