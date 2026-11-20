#!/usr/bin/env bash
# Parse the entire installer before running it when piped from curl.
{
set -euo pipefail

unattended=false
server_url=''
server_pattern='^https://([[:alnum:]-]+(\.[[:alnum:]-]+)*|\[[0-9a-fA-F:]+\])(:[0-9]{1,5})?/?$'

normalize_netbird_url() {
    local url=$1
    [[ $url == *://* ]] || url="https://$url"
    [[ $url =~ $server_pattern ]] || return 1
    printf '%s\n' "${url%/}"
}

while (( $# )); do
    case "$1" in
        --unattended)
            unattended=true
            shift
            ;;
        --netbird-url)
            if (( $# < 2 )) || ! server_url=$(normalize_netbird_url "$2"); then
                echo 'Pass a NetBird hostname or HTTPS URL to --netbird-url.' >&2
                exit 2
            fi
            shift 2
            ;;
        -h|--help)
            echo 'Usage: install-office.sh [--unattended --netbird-url HOST_OR_HTTPS_URL]'
            exit
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

if $unattended && [[ -z $server_url ]]; then
    echo '--unattended requires --netbird-url HOST_OR_HTTPS_URL.' >&2
    exit 2
fi

if [[ $(uname -m) != x86_64 || ! -e /run/ostree-booted || $EUID == 0 ]]; then
    echo 'Run this as your regular user on installed x86_64 Fedora Kinoite.' >&2
    exit 1
fi

as_root=(sudo)
if $unattended; then
    as_root+=(-n)
    if ! "${as_root[@]}" /usr/bin/true 2>/dev/null; then
        if ! ( : </dev/tty ) 2>/dev/null; then
            echo 'Unattended provisioning needs non-interactive sudo when run without a terminal.' >&2
            exit 1
        fi
        echo 'Authorize sudo once to start unattended setup.'
        sudo -v </dev/tty || exit 1
        "${as_root[@]}" /usr/bin/true || exit 1
    fi
    if ( : </dev/tty ) 2>/dev/null; then
        # Keep the terminal's sudo credential valid during long downloads.
        (
            while sudo -n -v; do
                sleep 60
            done
        ) </dev/null >/dev/null 2>&1 &
        sudo_refresh_pid=$!
        trap 'kill "$sudo_refresh_pid" 2>/dev/null || true' EXIT
    fi
    exec </dev/null
fi

download() {
    curl --proto '=https' --proto-redir '=https' --fail --silent --show-error \
        --location --retry 3 --output "$2" "$1"
}

install_anyk_launcher() {
    local destination=$1
    local applications="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    local desktop_path
    desktop_path=$(printf '%s' "$destination" | sed 's/\\/\\\\/g') || return
    mkdir -p "$applications" || return
    cat > "$applications/kinoite-office-anyk.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=ÁNYK (AbevJava)
Comment=NAV nyomtatványkitöltő
Keywords=ÁNYK;ANYK;AbevJava;NAV;
Icon=office-document
Path=$desktop_path
Exec=/usr/bin/bash ./abevjava_start
Terminal=false
Categories=Office;
DESKTOP
}

install_anyk() (
    destination="$HOME/abevjava"
    if [[ -s "$destination/abevjava.jar" && -x "$destination/abevjava_start" && -f "$destination/setenv" ]]; then
        echo "ÁNYK is already installed in $destination."
        install_anyk_launcher "$destination"
        exit $?
    fi

    path_config="$HOME/.abevjava/abevjavapath.cfg"
    if [[ -f "$path_config" ]]; then
        configured_path=$(sed -n 's/^[[:space:]]*abevjava\.path[[:space:]]*=[[:space:]]*//p' "$path_config" | tail -n 1)
        if [[ $configured_path != "$destination" ]]; then
            if [[ $configured_path == /* && -s "$configured_path/abevjava.jar" && -x "$configured_path/abevjava_start" ]]; then
                echo "ÁNYK is already installed in $configured_path."
                install_anyk_launcher "$configured_path"
                exit $?
            fi
            echo "ÁNYK has a different installation path in $path_config. Check it before retrying." >&2
            exit 1
        fi
    else
        mkdir -p "$HOME/.abevjava" || exit 1
        (set -o noclobber; printf 'abevjava.path=%s\n' "$destination" > "$path_config") || exit 1
    fi

    java_root="${XDG_DATA_HOME:-$HOME/.local/share}/kinoite-anyk"
    java_home="$java_root/temurin-8u514-b01"
    mkdir -p "$java_root" || exit 1
    workdir=$(mktemp -d "$java_root/.install.XXXXXXXX") || exit 1
    trap 'rm -rf -- "$workdir"' EXIT

    if [[ ! -x "$java_home/bin/java" ]]; then
        archive="$workdir/temurin.tar.gz"
        download 'https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u514-b01/OpenJDK8U-jre_x64_linux_hotspot_8u514b01.tar.gz' "$archive" || exit 1
        printf '%s  %s\n' b3e38dc60261a548fe83d297bf6faf7880f1b84f7d48e5741f3c6f3c3021cd4d "$archive" | sha256sum --check || exit 1
        mkdir "$workdir/java" || exit 1
        tar -xzf "$archive" --strip-components=1 -C "$workdir/java" || exit 1
        "$workdir/java/bin/java" -version || exit 1
        mv -T "$workdir/java" "$java_home" || exit 1
    fi

    download 'https://nav.gov.hu/pfile/programFile?path=/nyomtatvanyok/letoltesek/nyomtatvanykitolto_programok/nyomtatvany_apeh/keretprogramok/AbevJava' "$workdir/abevjava_install.jar" || exit 1
    JAVA_HOME="$java_home" PATH="$java_home/bin:$PATH" "$java_home/bin/java" \
        -Duser.home="$HOME" -Djava.awt.headless=true -jar "$workdir/abevjava_install.jar" -s </dev/null || exit 1

    if [[ ! -s "$destination/abevjava.jar" || ! -x "$destination/abevjava_start" || ! -f "$destination/setenv" ]]; then
        echo "ÁNYK installation is incomplete. See $HOME/abevjava_silent_install.log." >&2
        exit 1
    fi

    # NAV's launcher sources setenv and prepends JAVA_HOME_ABEV to its java command.
    if ! grep -q '^JAVA_HOME_ABEV=' "$destination/setenv"; then
        printf '\n%s\n' 'JAVA_HOME_ABEV="${XDG_DATA_HOME:-$HOME/.local/share}/kinoite-anyk/temurin-8u514-b01/bin/"' >> "$destination/setenv" || exit 1
    fi
    install_anyk_launcher "$destination" || exit 1
    echo 'Open ÁNYK (AbevJava) from the application menu.'
)

install_desktop_defaults() (
    local workdir shared_dir=/var/local/kinoite-office-bootstrap
    local autostart=/etc/skel/.config/autostart
    workdir=$(mktemp -d) || exit 1
    trap 'rm -rf -- "$workdir"' EXIT

    download 'https://raw.githubusercontent.com/buzag/kinoite-office-bootstrap/refs/heads/main/identigo-szekhely-wallpaper.png' "$workdir/wallpaper.png" || exit 1
    printf '%s  %s\n' 7ea277cda1c93a1fd5ecc4b2a859d18adeac95784025c112b884d62dd73bd722 "$workdir/wallpaper.png" | sha256sum --check || exit 1

    cat > "$workdir/apply-wallpaper" <<'SCRIPT' || exit 1
#!/usr/bin/env bash
wallpaper=/var/local/kinoite-office-bootstrap/identigo-szekhely-wallpaper.png
for ((attempt = 0; attempt < 30; attempt++)); do
    if plasma-apply-wallpaperimage "$wallpaper"; then
        kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image || exit 1
        kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "file://$wallpaper" || exit 1
        rm -f -- "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/kinoite-office-wallpaper.desktop"
        exit
    fi
    sleep 2
done
exit 1
SCRIPT

    cat > "$workdir/kinoite-office-wallpaper.desktop" <<'DESKTOP' || exit 1
[Desktop Entry]
Type=Application
Name=Set office wallpaper
OnlyShowIn=KDE;
TryExec=plasma-apply-wallpaperimage
Exec=/usr/bin/bash /var/local/kinoite-office-bootstrap/apply-wallpaper
DESKTOP

    user_dir="$HOME/.local/share/kinoite-office-bootstrap"
    user_autostart="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
    mkdir -p "$user_dir" "$user_autostart" || exit 1

    # System-wide defaults are optional and must never start a sudo prompt.
    if sudo -n install -d -m 0755 "$shared_dir" &&
       sudo -n mkdir -p "$autostart" &&
       sudo -n install -m 0644 "$workdir/wallpaper.png" "$shared_dir/identigo-szekhely-wallpaper.png" &&
       sudo -n install -m 0644 "$workdir/apply-wallpaper" "$shared_dir/apply-wallpaper" &&
       sudo -n install -m 0644 "$workdir/kinoite-office-wallpaper.desktop" "$autostart/"; then
        echo 'Installed the default wallpaper for new accounts.'
    else
        echo 'System-wide wallpaper setup unavailable. Applying it for this user.'
        install -m 0644 "$workdir/wallpaper.png" "$user_dir/identigo-szekhely-wallpaper.png" || exit 1
    fi

    cat > "$user_dir/apply-desktop" <<'SCRIPT' || exit 1
#!/usr/bin/env bash
set -euo pipefail
user_dir="$HOME/.local/share/kinoite-office-bootstrap"
wallpaper="$user_dir/identigo-szekhely-wallpaper.png"

# A generic browser pin represents Firefox on stock Kinoite.
browser=$(xdg-settings get default-web-browser 2>/dev/null || true)
remove_default_browser=false
case "$browser" in
    ''|firefox.desktop|org.mozilla.firefox.desktop) remove_default_browser=true ;;
esac

panel_script=$(cat <<JS
const removeDefaultBrowser = $remove_default_browser;
const defaults = "applications:systemsettings.desktop,applications:org.kde.discover.desktop,preferred://filemanager,preferred://browser";
for (const panel of panels()) {
    for (const widget of panel.widgets()) {
        if (!["org.kde.plasma.icontasks", "org.kde.plasma.taskmanager"].includes(widget.type)) {
            continue;
        }
        widget.currentConfigGroup = ["General"];
        const launchers = String(widget.readConfig("launchers", defaults)).split(",");
        const remaining = launchers.filter((launcher) => {
            const id = launcher.split("?")[0].split(/[/:]/).pop().toLowerCase();
            if (removeDefaultBrowser && launcher === "preferred://browser") return false;
            return !/^(firefox|org\.mozilla\.firefox|org\.kde\.discover|systemsettings|org\.kde\.systemsettings)\.desktop$/.test(id);
        });
        if (remaining.length !== launchers.length) {
            widget.writeConfig("launchers", remaining.join(","));
        }
    }
}
JS
)
for ((attempt = 0; attempt < 30; attempt++)); do
    if busctl --user --timeout=5s call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$panel_script"; then
        if [[ -f "$wallpaper" ]]; then
            plasma-apply-wallpaperimage "$wallpaper"
            kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image
            kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "file://$wallpaper"
        fi
        rm -f -- "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/kinoite-office-desktop.desktop"
        exit
    fi
    sleep 2
done
exit 1
SCRIPT

    cat > "$user_autostart/kinoite-office-desktop.desktop" <<'DESKTOP' || exit 1
[Desktop Entry]
Type=Application
Name=Apply office desktop defaults
OnlyShowIn=KDE;
Exec=/usr/bin/bash -c "exec /usr/bin/bash ~/.local/share/kinoite-office-bootstrap/apply-desktop"
DESKTOP
    echo 'Panel shortcuts will be updated at the next Plasma login.'

)

install_craft_app() {
    local ref="app/ai.storyteller.$1/x86_64/stable"
    local origin
    if origin=$(flatpak info --user --show-origin "$ref" 2>/dev/null); then
        if [[ $origin == artcraft-oci ]]; then
            return
        fi
        printf 'Switching %s from %s to ArtCraft.\n' "$1" "$origin"
        flatpak install --user --noninteractive --assumeyes --reinstall artcraft-oci "$ref"
        return
    fi
    flatpak install --user --noninteractive --assumeyes artcraft-oci "$ref"
}

enable_netbird_service() {
    if [[ -x /usr/bin/netbird ]]; then
        if [[ $(systemctl show --property=LoadState --value netbird.service) == not-found ]]; then
            "${as_root[@]}" /usr/bin/netbird service install || return
        fi
        "${as_root[@]}" systemctl enable --now --no-block netbird.service
        return
    fi

    # The RPM is staged, so its executable may only exist after reboot.
    "${as_root[@]}" tee /etc/systemd/system/office-netbird-enable.service >/dev/null <<'UNIT' || return
[Unit]
Description=Enable NetBird after the staged RPM is booted
ConditionPathIsExecutable=/usr/bin/netbird

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c 'if [[ $(systemctl show --property=LoadState --value netbird.service) == not-found ]]; then /usr/bin/netbird service install || exit 1; fi; exec systemctl enable --now netbird.service'
ExecStartPost=/usr/bin/systemctl --no-reload disable office-netbird-enable.service

[Install]
WantedBy=multi-user.target
UNIT
    "${as_root[@]}" systemctl enable office-netbird-enable.service
}

schedule_netbird_signin() {
    local url=$1
    local units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    mkdir -p "$units" || return
    cat > "$units/office-netbird-signin.service" <<UNIT || return
[Unit]
Description=Complete NetBird sign-in
After=graphical-session-pre.target
PartOf=graphical-session.target
ConditionPathIsExecutable=/usr/bin/netbird

[Service]
Type=exec
RuntimeMaxSec=10min
ExecStart=/usr/bin/bash -c 'for ((attempt=0; attempt<30; attempt++)); do if /usr/bin/netbird status --check live; then if /usr/bin/netbird status --check ready || /usr/bin/netbird up --management-url "$url"; then exec systemctl --user --no-reload disable office-netbird-signin.service; fi; exit 1; fi; sleep 2; done; exit 1'

[Install]
WantedBy=graphical-session.target
UNIT
    systemctl --user enable office-netbird-signin.service || return
    if [[ -x /usr/bin/netbird ]]; then
        systemctl --user start --no-block office-netbird-signin.service || return
        echo 'Complete NetBird sign-in in the browser when it opens.'
    else
        echo 'After reboot and desktop login, complete NetBird sign-in in the browser when it opens.'
    fi
}

seed_netbird_profile() {
    "${as_root[@]}" python3 - "$1" <<'PYTHON'
import json
import os
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlsplit

url = urlsplit(sys.argv[1])
profile = Path("/var/lib/netbird/default.json")
server = {"Scheme": url.scheme, "Host": url.netloc}
if profile.exists():
    with profile.open() as source:
        current = json.load(source).get("ManagementURL") or {}
    current_host = current.get("Host", "").lower().removesuffix(":443")
    if current.get("Scheme") == url.scheme and current_host == url.netloc.lower().removesuffix(":443"):
        sys.exit(0)
    sys.exit("NetBird already has a profile for another server. Existing settings were preserved.")

if Path("/etc/netbird/config.json").exists() or (profile.parent / "active_profile.json").exists():
    sys.exit("NetBird already has configuration state. Existing settings were preserved.")

os.umask(0o077)
profile.parent.mkdir(parents=True, exist_ok=True)
# Publish the complete file atomically without overwriting an existing profile.
with tempfile.NamedTemporaryFile(mode="w", dir=profile.parent) as target:
    json.dump({"ManagementURL": server, "AdminURL": server}, target)
    target.write("\n")
    target.flush()
    os.link(target.name, profile)
PYTHON
}

install_netbird() {
    local url=$server_url
    if [[ -z $url ]] && ! netbird status --check ready >/dev/null 2>&1; then
        while true; do
            read -r -p 'NetBird server URL (Enter for NetBird Cloud): ' url </dev/tty || return
            if url=$(normalize_netbird_url "${url:-https://api.netbird.io:443}"); then
                break
            fi
            echo 'Enter a hostname or an HTTPS URL, optionally with a port.' >&2
        done
    fi

    if [[ ! -e /etc/yum.repos.d/netbird.repo ]]; then
        "${as_root[@]}" tee /etc/yum.repos.d/netbird.repo >/dev/null <<'REPO' || return
[netbird]
name=NetBird
baseurl=https://pkgs.netbird.io/yum/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.netbird.io/yum/repodata/repomd.xml.key
REPO
    fi
    "${as_root[@]}" rpm-ostree install --idempotent --allow-inactive netbird-ui gtk4 webkitgtk6.0 xdg-utils || return
    if $unattended; then
        seed_netbird_profile "$url" || return
        # Remove a pending browser login scheduled by an earlier interactive run.
        rm -f -- "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/graphical-session.target.wants/office-netbird-signin.service" || return
        enable_netbird_service || return
        printf 'NetBird sign-in is deferred. To connect later: netbird up --management-url %q\n' "$url"
        return
    fi
    enable_netbird_service || return
    if [[ -n $url ]]; then
        schedule_netbird_signin "$url"
    else
        echo 'NetBird is already configured.'
    fi
}

configure_browser() {
    local chrome_id mime package state deployment
    local -a layered=() base=()
    if rpm -q google-chrome-stable >/dev/null 2>&1; then
        chrome_id=google-chrome.desktop
    elif flatpak info com.google.Chrome >/dev/null 2>&1; then
        chrome_id=com.google.Chrome.desktop
    else
        echo 'Chrome is unavailable. Firefox was retained.' >&2
        return 1
    fi

    # Write the desktop defaults directly so this also works before first login.
    mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}" || return
    for mime in x-scheme-handler/http x-scheme-handler/https text/html; do
        kwriteconfig6 --file mimeapps.list --group 'Default Applications' --key "$mime" "$chrome_id;" || return
        kwriteconfig6 --file kde-mimeapps.list --group 'Default Applications' --key "$mime" "$chrome_id;" || return
    done
    kwriteconfig6 --file kdeglobals --group General --key BrowserApplication "$chrome_id" || return

    if flatpak info --user org.mozilla.firefox >/dev/null 2>&1; then
        flatpak uninstall --user --noninteractive --assumeyes org.mozilla.firefox || return
    fi
    if flatpak info --system org.mozilla.firefox >/dev/null 2>&1; then
        "${as_root[@]}" flatpak uninstall --system --noninteractive --assumeyes org.mozilla.firefox || return
    fi

    if rpm -q firefox >/dev/null 2>&1 || rpm -q firefox-langpacks >/dev/null 2>&1; then
        deployment=$(rpm-ostree status --json | python3 -c '
import json, sys
deployments = json.load(sys.stdin)["deployments"]
deployment = deployments[0]
booted = next(item for item in deployments if item.get("booted"))
layered = set(deployment.get("requested-packages", []))
removed = set(deployment.get("requested-base-removals", []))
removed.update(set(booted.get("requested-packages", [])) - layered)
for package in removed:
    print("removed", package)
for package in layered - removed:
    print("layered", package)
') || return
        for package in firefox firefox-langpacks; do
            rpm -q "$package" >/dev/null 2>&1 || continue
            state=$(printf '%s\n' "$deployment" | awk -v package="$package" '$2 == package {print $1; exit}')
            case $state in
                removed) ;;
                layered) layered+=("$package") ;;
                *) base+=("$package") ;;
            esac
        done
        if (( ${#layered[@]} )); then
            "${as_root[@]}" rpm-ostree uninstall "${layered[@]}" || return
        fi
        if (( ${#base[@]} )); then
            "${as_root[@]}" rpm-ostree override remove "${base[@]}" || return
        fi
    fi
}

failed=()
install_step() {
    local label=$1
    shift
    printf '\n==> %s\n' "$label"
    if "$@"; then
        printf 'OK: %s\n' "$label"
    else
        printf 'Failed: %s\n' "$label" >&2
        failed+=("$label")
    fi
}

install_step NetBird install_netbird

install_step Flathub flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
if rpm -q google-chrome-stable >/dev/null 2>&1 || flatpak info com.google.Chrome >/dev/null 2>&1; then
    echo 'OK: Google Chrome is already installed.'
else
    install_step 'Google Chrome' flatpak install --user --noninteractive --assumeyes flathub com.google.Chrome
fi
install_step 'Default browser and Firefox removal' configure_browser
install_step Dropbox flatpak install --user --noninteractive --assumeyes flathub com.dropbox.Client
install_step Discord flatpak install --user --noninteractive --assumeyes flathub com.discordapp.Discord
install_step 'ArtCraft repository' flatpak remote-add --user --if-not-exists artcraft-oci https://getartcraft.com/artcraft-oci.flatpakrepo
install_step WordCraft install_craft_app wordcraft
install_step GridCraft install_craft_app gridcraft

install_step ÁNYK install_anyk
install_step 'Wallpaper and panel shortcuts' install_desktop_defaults

if (( ${#failed[@]} )); then
    printf '\nFailed steps:\n' >&2
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi
}
