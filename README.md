# Fedora Kinoite office setup

On an installed **64-bit Intel or AMD Fedora Kinoite** desktop, open Konsole as your regular user and copy the line for the setup you want. Each installer runs independently. The office and scanner installers ask for administrator access and need a reboot to activate system packages.

## Office apps and ÁNYK

Installs NetBird, WordCraft, GridCraft, PdfCraft, Google Chrome, Dropbox, Discord, and ÁNYK (AbevJava).

The installer sets Chrome as the default browser for the current user and removes Firefox once Chrome is available. Chrome is pinned to the KDE panel at the next Plasma login. GridCraft opens .xlsx and .xls, WordCraft opens .docx and .doc, and PdfCraft opens .pdf by default. Firefox RPM removal takes effect after reboot.

With non-interactive sudo access, new accounts get the identiGO / SzékhelySzolgálat image as both the desktop and lock-screen wallpaper on their first Plasma login. The system login screen also uses the same image at the next boot on systems using Plasma Login Manager, the default on fresh Kinoite 44 and later. If that setup is unavailable, the installer queues both wallpaper changes for the current user instead. The current user’s Firefox, Discover, and System Settings panel shortcuts are removed at the next Plasma login. Other shortcuts stay in place.

```bash
curl -fsSL https://raw.githubusercontent.com/buzag/kinoite-office-bootstrap/refs/heads/main/install-office.sh | bash
```

At the start, enter your NetBird server hostname or HTTPS URL. Press Enter for NetBird Cloud. The installer adds HTTPS to a bare hostname and skips sign-in for an already configured client. After reboot and desktop login, NetBird starts automatically. Complete the sign-in in the browser when it opens. Open Dropbox and Discord from the application menu to sign in.

The NetBird desktop app installs first from its signed RPM repository. Chrome, Dropbox, and Discord are installed per user from Flathub. An existing Chrome installation is reused. WordCraft, GridCraft, and PdfCraft are installed per user from the [official ArtCraft Flatpak repository](https://getartcraft.com/linux).

Discover can update all six Flatpak apps in the background when **Unattended Updates** is enabled in KDE's Software Update settings. If you ran an earlier version of this installer, close WordCraft and GridCraft and rerun the office command to switch their existing per-user Flatpak installations to ArtCraft. Flatpak preserves their app data.

If a step fails, the installer attempts the rest and lists failed steps at the end. You can rerun the same command. After reboot, open **NetBird** from the application menu. Use `systemctl is-active netbird.service` to check the daemon and `netbird status` to check the connection. A running daemon reports `active`. A working connection shows **Management: Connected** and **Signal: Connected**.

ÁNYK installs silently into `$HOME/abevjava` with a per-user Temurin Java 8 runtime. The installer adds a searchable **ÁNYK (AbevJava)** shortcut to the current user’s application menu, including when the app is already installed. If setup fails, check `$HOME/abevjava_silent_install.log`. See [NAV’s installation guide](https://nav.gov.hu/pfile/file?path=%2Fnyomtatvanyok%2Fletoltesek%2Fnyomtatvanykitolto_programok%2Fnyomtatvany_apeh%2Fkeretprogramok%2Fld_abevjava%2FTelepitesi_leiras_2017.12.13._).

### Unattended provisioning

```bash
curl -fsSL https://raw.githubusercontent.com/buzag/kinoite-office-bootstrap/refs/heads/main/install-office.sh | bash -s -- --unattended --netbird-url netbird.example.com
```

Replace `netbird.example.com` with your management server hostname or HTTPS URL. Run as the desktop user. When pasted into Konsole by a sudo-enabled user, the script asks for sudo authorization at the start if needed, then continues unattended. In Ventoy first-boot provisioning, the media builder supplies temporary passwordless sudo, and the script runs without a terminal or password prompt.

NetBird starts using the supplied server as soon as the installed package is available, which may require the next reboot. The installer does not open a browser or wait for NetBird login. When ready to connect, open **NetBird** from the application menu or run `netbird up --management-url https://netbird.example.com` and complete browser sign-in. An existing profile for a different server is preserved and reported as a failed NetBird step.

You can rerun the same command between reboots. A rerun reuses the NetBird profile for the same server. The script attempts the remaining installers after a failed step and exits with a nonzero status if any step fails. Your provisioning system controls when to reboot.

## Brother ADS-4100 scanner

```bash
curl -fsSL https://raw.githubusercontent.com/buzag/kinoite-office-bootstrap/refs/heads/main/install-scanner.sh | bash
```

Review the [Brother driver license](https://support.brother.com/g/s/agreement/English_lpr/agree.html) before accepting it in the terminal. The installer layers Brother's `brscan5` RPM, SANE tools, and Skanpage. After reboot, connect and power on the scanner over USB, run `scanimage -L`, then test a multi-page scan in Skanpage.

## Installation media builder

The experimental [Ventoy config generator](MEDIA-BUILDER.md) prepares a Kickstart file and Ventoy configuration for a single Fedora Kinoite USB. The guide includes a copy-paste prompt for Codex or Claude to create the USB.
