#!/usr/bin/env bash
set -Eeuo pipefail

# modern-labwc -> Debian testing (Forky)
# Run this script from the root of a cloned modern-labwc repository.

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { printf '%b\n' "${BLUE}[modern-labwc]${NC} $*"; }
ok()   { printf '%b\n' "${GREEN}[OK]${NC} $*"; }
warn() { printf '%b\n' "${YELLOW}[WARN]${NC} $*"; }
die()  { printf '%b\n' "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ "$(id -u)" -ne 0 ]] || die "不要用 root 运行。请用普通用户运行，脚本会在需要时调用 sudo。"
command -v sudo >/dev/null 2>&1 || die "缺少 sudo。先安装 sudo 并确保当前用户可使用它。"
command -v apt-get >/dev/null 2>&1 || die "没有检测到 apt-get。这个脚本只针对 Debian testing。"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[[ -f setup.sh && -d config && -f fonts.tar.xz && -f Bibata-Modern-Ice.tar.xz && -f themes.tar.xz ]] \
  || die "请把脚本放在 modern-labwc 仓库根目录中运行。"

# Debian testing is currently codenamed Forky. Accept an exact Forky system or a
# testing installation whose /etc/os-release still reports VERSION_ID differently.
. /etc/os-release
if [[ "${ID:-}" != "debian" ]]; then
    die "当前系统不是 Debian。"
fi
if [[ "${VERSION_CODENAME:-}" != "forky" && "${VERSION_CODENAME:-}" != "testing" ]]; then
    warn "当前 VERSION_CODENAME=${VERSION_CODENAME:-unknown}；脚本按 Debian testing/Forky 的包名设计。"
fi

log "安装 Debian 原生依赖……"
sudo apt-get update

APT_PACKAGES=(
    imagemagick
    labwc
    wl-clipboard
    cliphist
    waybar
    rofi
    ffmpegthumbnailer
    ffmpeg
    dunst
    foot
    swayidle
    hyprlock
    qtwayland5
    qt5ct
    qt6ct
    qt6-wayland
    network-manager
    nm-connection-editor
    lxqt-policykit
    gnome-keyring
    wf-recorder
    grim
    gammastep
    mpv-mpris
    slurp
    swayimg
    playerctl
    pavucontrol
    pamixer
    brightnessctl
    xdg-desktop-portal
    xdg-desktop-portal-wlr
    xdg-desktop-portal-gtk
    thunar
    xfce4-taskmanager
    jq
    feh
    curl
    yt-dlp
    socat
    mpv
    netcat-openbsd
    python3
    python3-watchdog
    alsa-utils
    wtype
    libnotify-bin
    libglib2.0-bin
    dconf-gsettings-backend
    gsettings-desktop-schemas
    fontconfig
    fonts-font-awesome
    fonts-inter
    fonts-roboto
    papirus-icon-theme
    git
    cargo
    rustc
    build-essential
    pkg-config
    libwayland-dev
    wayland-protocols
    liblz4-dev
    ca-certificates
)

# wl-clip-persist is not required for the rest of the desktop. Keep it optional;
# the autostart below is patched to skip it when absent.
sudo apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}"
ok "Debian 依赖安装完成。"

install_cargo_binary() {
    local name="$1"
    if command -v "$name" >/dev/null 2>&1; then
        ok "$name 已存在：$(command -v "$name")"
        return 0
    fi
    log "通过 Cargo 安装 $name……"
    cargo install --locked "$name"
    [[ -x "$HOME/.cargo/bin/$name" ]] || die "Cargo 安装 $name 后没有找到 ~/.cargo/bin/$name"
    sudo install -Dm755 "$HOME/.cargo/bin/$name" "/usr/local/bin/$name"
    ok "$name 已安装到 /usr/local/bin/$name"
}

# matugen is intentionally installed from crates.io instead of relying on an
# Arch-only package name from upstream setup.sh.
install_cargo_binary matugen

# awww is the current successor/rename of swww used by the repository's current
# autostart/wallpaper scripts. Build it from the upstream Codeberg repository.
if ! command -v awww >/dev/null 2>&1 || ! command -v awww-daemon >/dev/null 2>&1; then
    log "构建 awww（swww 的新命名）……"
    TMP_AWWW="$(mktemp -d)"
    trap 'rm -rf "${TMP_AWWW:-}"' EXIT
    git clone --depth 1 https://codeberg.org/LGFae/awww.git "$TMP_AWWW/awww"
    cargo build --release --manifest-path "$TMP_AWWW/awww/Cargo.toml"
    [[ -x "$TMP_AWWW/awww/target/release/awww" ]] || die "awww 构建成功但找不到 awww 二进制。"
    [[ -x "$TMP_AWWW/awww/target/release/awww-daemon" ]] || die "awww 构建成功但找不到 awww-daemon 二进制。"
    sudo install -Dm755 "$TMP_AWWW/awww/target/release/awww" /usr/local/bin/awww
    sudo install -Dm755 "$TMP_AWWW/awww/target/release/awww-daemon" /usr/local/bin/awww-daemon
    ok "awww/awww-daemon 已安装。"
else
    ok "awww 已存在。"
fi

# Backup only the directories that this repository will replace.
BACKUP_ROOT="$HOME/.config/BACKUP"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$STAMP"
mkdir -p "$HOME/.config"

log "备份现有配置……"
BACKUP_ANY=0
for src in "$SCRIPT_DIR/config"/*; do
    [[ -e "$src" ]] || continue
    name="$(basename "$src")"
    if [[ -e "$HOME/.config/$name" ]]; then
        mkdir -p "$BACKUP_DIR"
        mv "$HOME/.config/$name" "$BACKUP_DIR/"
        BACKUP_ANY=1
    fi
done
if (( BACKUP_ANY )); then
    ok "旧配置已备份到 $BACKUP_DIR"
else
    ok "没有需要备份的旧配置。"
fi

log "复制 modern-labwc 配置……"
find "$SCRIPT_DIR/config" -type f -name '*.sh' -exec chmod +x {} +
cp -a "$SCRIPT_DIR/config/." "$HOME/.config/"

# The upstream files contain an author-specific Qt5 path and a non-shell-expanding
# $HOME in the Qt6 path. Fix both for the current user.
QT5_CONF="$HOME/.config/qt5ct/qt5ct.conf"
QT6_CONF="$HOME/.config/qt6ct/qt6ct.conf"
if [[ -f "$QT5_CONF" ]]; then
    sed -i "s|^color_scheme_path=.*|color_scheme_path=$HOME/.config/qt5ct/colors/wallpaper.conf|" "$QT5_CONF"
fi
if [[ -f "$QT6_CONF" ]]; then
    sed -i "s|^color_scheme_path=.*|color_scheme_path=$HOME/.config/qt6ct/colors/wallpaper.conf|" "$QT6_CONF"
fi

# The current repo's Waybar config assumes xfce4-terminal exists, while the
# dependency list only guarantees foot. Use foot for the primary terminal action.
WAYBAR_CONF="$HOME/.config/waybar/config.jsonc"
if [[ -f "$WAYBAR_CONF" ]]; then
    sed -i 's/"on-click": "xfce4-terminal"/"on-click": "foot"/' "$WAYBAR_CONF"
fi

# Make wl-clip-persist optional, so the rest of the clipboard stack works on
# Debian without an extra non-Debian package.
AUTOSTART="$HOME/.config/labwc/autostart"
if [[ -f "$AUTOSTART" ]]; then
    awk 'BEGIN {done=0} {
        if ($0 == "wl-clip-persist --clipboard regular &") {
            print "if command -v wl-clip-persist >/dev/null 2>&1; then"
            print "    wl-clip-persist --clipboard regular &"
            print "fi"
            done=1
        } else print
    } END { if (!done) exit 0 }' "$AUTOSTART" > "$AUTOSTART.tmp"
    mv "$AUTOSTART.tmp" "$AUTOSTART"
fi

# Ensure local wallpapers exist and point the selector at a user-writable path.
WALL_DIR="$HOME/Pictures/Wallpapers"
mkdir -p "$WALL_DIR" "$HOME/.cache/wallselect/thumbnails"
WALL_SCRIPT="$HOME/.config/rofi/wallselect/wallselect.sh"
if [[ -f "$WALL_SCRIPT" ]]; then
    sed -i "s|^wall_dir=.*|wall_dir=\"$WALL_DIR\"|" "$WALL_SCRIPT"
fi

log "安装仓库自带字体、光标和 labwc 主题……"
mkdir -p "$HOME/.local/share" "$HOME/.local/share/icons" "$HOME/.themes"
tar -xJf "$SCRIPT_DIR/fonts.tar.xz" -C "$HOME/.local/share"
tar -xJf "$SCRIPT_DIR/Bibata-Modern-Ice.tar.xz" -C "$HOME/.local/share/icons"
tar -xJf "$SCRIPT_DIR/themes.tar.xz" -C "$HOME/.themes"
fc-cache -f >/dev/null

log "生成 labwc 根菜单……"
MENU_GENERATOR="$HOME/.config/labwc/menu-generator.py"
MENU_FILE="$HOME/.config/labwc/menu.xml"
if [[ -f "$MENU_GENERATOR" ]]; then
    python3 "$MENU_GENERATOR" -o "$MENU_FILE" || warn "根菜单生成失败；进入 labwc 后按 Super+G 再生成一次。"
fi

# The upstream setup script adds users to input/seat. That is not needed for a
# normal Debian system using systemd-logind and is intentionally omitted here.

# Useful session environment for the scripts. Do not force QT_QPA_PLATFORMTHEME,
# because Qt5ct and Qt6ct require different values; the repo's per-version configs
# are installed and can be selected in the user's session environment.
ENV_DIR="$HOME/.config/environment.d"
mkdir -p "$ENV_DIR"
cat > "$ENV_DIR/90-modern-labwc.conf" <<'ENVEOF'
# modern-labwc
# Uncomment ONE of the following when you want qtct to control Qt applications.
# QT_QPA_PLATFORMTHEME=qt5ct
# QT_QPA_PLATFORMTHEME=qt6ct
ENVEOF

# A simple helper for starting the compositor from a TTY, useful on a no-DE install.
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/start-modern-labwc" <<'EOFSTART'
#!/usr/bin/env bash
exec dbus-run-session labwc "$@"
EOFSTART
chmod +x "$HOME/.local/bin/start-modern-labwc"

ok "modern-labwc 已移植到 Debian testing。"
printf '\n'
printf '%b\n' "${GREEN}下一步：${NC}"
printf '  1. 把壁纸放入：%s\n' "$WALL_DIR"
printf '  2. 重新登录 Wayland labwc 会话。\n'
printf '  3. 无显示管理器时可运行：start-modern-labwc\n'
printf '  4. Super+Enter 打开 foot；Super+D 打开 Rofi。\n'
printf '  5. Super+B 打开壁纸选择器；Super+R 重载 labwc。\n'
printf '\n'
warn "仓库中的浏览器/编辑器快捷键仍保留原作者命令（Chrome/Brave/Thorium/Sublime）；请按你的 Debian 软件替换。"
warn "仓库默认通知守护进程是 dunst，但 Waybar 的通知模块还兼容 swaync；未安装 swaync 时该模块可能不显示通知状态。"
