# Fedora Kinoite office setup

On an installed **64-bit Intel or AMD Fedora Kinoite** desktop, open Konsole as your regular user and copy the line for the setup you want. Each installer runs independently. The office and scanner installers ask for administrator access and need a reboot to activate system packages.

## Office apps and ÁNYK

Installs NetBird, WordCraft, GridCraft, Google Chrome, Dropbox, Discord, ChatGPT desktop with Codex, and ÁNYK (AbevJava).

```bash
curl -fsSL https://raw.githubusercontent.com/buzag/kinoite-office-bootstrap/refs/heads/main/install-office.sh | bash
```

At the start, enter your NetBird server hostname or HTTPS URL. Press Enter for NetBird Cloud. The installer adds HTTPS to a bare hostname and skips sign-in for an already configured client. After reboot and desktop login, NetBird starts automatically. Complete the sign-in in the browser when it opens. Open Dropbox and Discord from the application menu to sign in.

NetBird installs first from its signed RPM repository. Chrome, Dropbox, and Discord are installed per user from Flathub. An existing Chrome installation is reused. WordCraft and GridCraft are installed per user from the [official ArtCraft Flatpak repository](https://getartcraft.com/linux).

Discover can update all five Flatpak apps in the background when **Unattended Updates** is enabled in KDE's Software Update settings. If you ran an earlier version of this installer, close WordCraft and GridCraft and rerun the office command to switch their existing per-user Flatpak installations to ArtCraft. Flatpak preserves their app data.

If a step fails, the installer attempts the rest and lists failed steps at the end. You can rerun the same command. NetBird is installed as a system service with a command-line client. After reboot, use `netbird version` to check that it is available.

ChatGPT desktop is layered from OpenAI’s signed RPM repository so it can update with the system. After reboot, open **ChatGPT**, sign in, and select **Codex**. OpenAI’s Linux desktop app is in preview. Its documented Fedora support is for Fedora 43 and 44. See the [OpenAI Linux desktop guide](https://learn.chatgpt.com/docs/linux/linux-app).

ÁNYK installs silently into `$HOME/abevjava` with a per-user Temurin Java 8 runtime. The installer skips existing installations. Launch it with `cd "$HOME/abevjava" && ./abevjava_start` after a fresh install. If setup fails, check `$HOME/abevjava_silent_install.log`. See [NAV’s installation guide](https://nav.gov.hu/pfile/file?path=%2Fnyomtatvanyok%2Fletoltesek%2Fnyomtatvanykitolto_programok%2Fnyomtatvany_apeh%2Fkeretprogramok%2Fld_abevjava%2FTelepitesi_leiras_2017.12.13._).

## Brother ADS-4100 scanner

```bash
curl -fsSL https://raw.githubusercontent.com/buzag/kinoite-office-bootstrap/refs/heads/main/install-scanner.sh | bash
```

Review the [Brother driver license](https://support.brother.com/g/s/agreement/English_lpr/agree.html) before accepting it in the terminal. The installer layers Brother's `brscan5` RPM, SANE tools, and Skanpage. After reboot, connect and power on the scanner over USB, run `scanimage -L`, then test a multi-page scan in Skanpage.
