# Kinoite office trial bootstrapper

This script is intended for an **installed Fedora Kinoite system on an external SSD**, not for a live USB session. It creates one new immutable deployment, so the Windows disk is never selected or altered.

It installs:

- NetBird (host service)
- Google Chrome (official RPM)
- Dropbox (official Fedora RPM)
- Brother ADS-4100 scanning stack: Brother's 64-bit RPM, SANE, and sane-airscan
- WordCraft and GridCraft as current per-user Flatpak bundles from their GitHub releases

## Publish safely

Before putting the script on GitHub, set these two variables near its top from the official Brother ADS-4100 Linux RPM download page:

```bash
BROTHER_RPM_URL="https://.../brscan5-...x86_64.rpm"
BROTHER_RPM_SHA256="64-character-sha256-value"
```

The checksum guard is intentional: Brother's download URLs and package versions change, and an installer should not silently accept a substituted driver.

After committing a reviewed, pinned script to a repository, run it with a versioned URL—not a mutable `main` branch URL:

```bash
curl -fsSLO https://raw.githubusercontent.com/OWNER/REPOSITORY/TAG/kinoite-office-bootstrap.sh
chmod +x kinoite-office-bootstrap.sh
./kinoite-office-bootstrap.sh
```

It stages system packages and installs the two user applications, then asks for one reboot. Dropbox and NetBird authentication remain interactive by design. After restarting, run `scanimage -L` with the ADS-4100 attached, and perform a real multi-page scan before depending on it.

For a temporary script test before publishing, pass the Brother RPM and its SHA-256 explicitly:

```bash
./kinoite-office-bootstrap.sh \
  --brother-rpm /path/to/brscan5-...x86_64.rpm \
  --brother-sha256 YOUR_64_CHARACTER_SHA256
```
