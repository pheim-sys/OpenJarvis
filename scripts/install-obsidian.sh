#!/usr/bin/env bash
set -euo pipefail

# ── Obsidian Installer ───────────────────────────────────────────────
# Installs the Obsidian desktop app (https://obsidian.md) on Linux or
# macOS and, optionally, creates a vault and connects it to OpenJarvis.
#
# Usage:
#   ./scripts/install-obsidian.sh                  # install Obsidian only
#   ./scripts/install-obsidian.sh --vault ~/Vault  # + create & connect vault
#
# Linux:  Flatpak (if available) → .deb (Debian/Ubuntu) → AppImage
# macOS:  Homebrew cask → DMG
# Windows: use scripts/install-obsidian.ps1 instead.
# ──────────────────────────────────────────────────────────────────────

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${BLUE}[info]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ok]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }
fail()  { echo -e "${RED}[fail]${NC}  $*"; exit 1; }

RELEASES_API="https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest"
RELEASES_DL="https://github.com/obsidianmd/obsidian-releases/releases/download"
FALLBACK_VERSION="1.8.10"

VAULT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault) VAULT="${2:?--vault needs a path}"; shift 2 ;;
    -h|--help) sed -n '4,15p' "$0"; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

command -v curl >/dev/null || fail "curl is required."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

latest_version() {
  local v
  v="$(curl -fsSL "$RELEASES_API" 2>/dev/null \
        | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')" || true
  if [[ -z "$v" ]]; then
    warn "Could not query latest release, falling back to v$FALLBACK_VERSION."
    v="$FALLBACK_VERSION"
  fi
  echo "$v"
}

download() {
  local url="$1" dest="$2"
  info "Downloading $url"
  curl -fL --progress-bar -o "$dest" "$url" || fail "Download failed: $url"
}

sudo_cmd() {
  if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

# ── Linux ────────────────────────────────────────────────────────────
install_linux() {
  if command -v flatpak >/dev/null; then
    info "Installing via Flatpak (md.obsidian.Obsidian)..."
    flatpak remote-add --user --if-not-exists flathub \
      https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak install --user -y flathub md.obsidian.Obsidian
    ok "Obsidian installed. Launch with: flatpak run md.obsidian.Obsidian"
    return
  fi

  local version arch
  version="$(latest_version)"
  arch="$(uname -m)"

  if command -v dpkg >/dev/null && command -v apt-get >/dev/null \
      && [[ "$arch" == "x86_64" ]]; then
    local deb="$TMP_DIR/obsidian_${version}_amd64.deb"
    download "$RELEASES_DL/v$version/obsidian_${version}_amd64.deb" "$deb"
    info "Installing .deb package (may ask for sudo password)..."
    sudo_cmd apt-get install -y "$deb"
    ok "Obsidian v$version installed. Launch with: obsidian"
    return
  fi

  local appimage_name
  case "$arch" in
    x86_64)         appimage_name="Obsidian-${version}.AppImage" ;;
    aarch64|arm64)  appimage_name="Obsidian-${version}-arm64.AppImage" ;;
    *) fail "Unsupported architecture: $arch" ;;
  esac

  local bin_dir="$HOME/.local/bin"
  mkdir -p "$bin_dir"
  download "$RELEASES_DL/v$version/$appimage_name" "$bin_dir/Obsidian.AppImage"
  chmod +x "$bin_dir/Obsidian.AppImage"
  ln -sf "$bin_dir/Obsidian.AppImage" "$bin_dir/obsidian"

  local apps_dir="$HOME/.local/share/applications"
  mkdir -p "$apps_dir"
  cat > "$apps_dir/obsidian.desktop" <<EOF
[Desktop Entry]
Name=Obsidian
Exec=$bin_dir/Obsidian.AppImage %U
Terminal=false
Type=Application
Categories=Office;
MimeType=x-scheme-handler/obsidian;
EOF
  ok "Obsidian v$version installed to $bin_dir/Obsidian.AppImage"
  [[ ":$PATH:" == *":$bin_dir:"* ]] || warn "Add $bin_dir to your PATH to run 'obsidian'."
  warn "AppImages need FUSE (e.g. 'sudo apt install libfuse2') on some distros."
}

# ── macOS ────────────────────────────────────────────────────────────
install_macos() {
  if command -v brew >/dev/null; then
    info "Installing via Homebrew cask..."
    brew install --cask obsidian
    ok "Obsidian installed to /Applications/Obsidian.app"
    return
  fi

  local version dmg mount_point
  version="$(latest_version)"
  dmg="$TMP_DIR/Obsidian-${version}.dmg"
  download "$RELEASES_DL/v$version/Obsidian-${version}.dmg" "$dmg"
  mount_point="$(hdiutil attach -nobrowse "$dmg" | tail -1 | cut -f3-)"
  cp -R "$mount_point/Obsidian.app" /Applications/
  hdiutil detach "$mount_point" -quiet
  ok "Obsidian v$version installed to /Applications/Obsidian.app"
}

# ── Main ─────────────────────────────────────────────────────────────
case "$(uname -s)" in
  Linux)  install_linux ;;
  Darwin) install_macos ;;
  *) fail "Unsupported OS. On Windows run scripts/install-obsidian.ps1." ;;
esac

if [[ -n "$VAULT" ]]; then
  VAULT="${VAULT/#\~/$HOME}"
  mkdir -p "$VAULT/.obsidian"
  if [[ ! -e "$VAULT/Welcome.md" ]]; then
    printf '# Welcome\n\nThis vault is indexed by OpenJarvis.\n' > "$VAULT/Welcome.md"
  fi
  ok "Vault ready at $VAULT"

  if command -v uv >/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    info "Connecting vault to OpenJarvis..."
    (cd "$SCRIPT_DIR/.." && uv run jarvis connect obsidian --path "$VAULT") \
      || warn "Connecting failed; run: uv run jarvis connect obsidian --path \"$VAULT\""
  else
    info "Connect it later with: uv run jarvis connect obsidian --path \"$VAULT\""
  fi
fi
