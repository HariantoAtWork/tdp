#!/usr/bin/env bash
#
# install.sh — curl|bash installer for tdp (GPD WIN 5 / Strix Halo TDP slider)
#
# Supports: NixOS, Ubuntu/Debian, Alpine Linux
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/HariantoAtWork/tdp/main/install.sh | sudo bash
#
# Options:
#   --step N         boot default step (1-9, default 5). Never installs step 10.
#   --no-service     install the binary only (no boot unit)
#   --prefix DIR     install binary here (default: /usr/local/bin)
#   --rebuild        NixOS only: add import + run nixos-rebuild switch
#   --uninstall      remove binary + boot unit
#   --yes            non-interactive
#
set -euo pipefail

REPO_RAW="${TDP_REPO_RAW:-https://raw.githubusercontent.com/HariantoAtWork/tdp/main}"
RYZENADJ_GIT="${TDP_RYZENADJ_GIT:-https://github.com/FlyGoat/RyzenAdj.git}"

STEP=5
INSTALL_SERVICE=1
PREFIX="/usr/local/bin"
UNINSTALL=0
REBUILD=0
UNIT_NAME="tdp"

w()  { printf 'tdp-install: %s\n' "$*" >&2; }
die(){ w "✗ $*"; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

need_root() {
  [[ "$(id -u)" == "0" ]] || die "run as root: curl … | sudo bash"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --step) STEP="${2:-}"; shift 2 ;;
    --no-service) INSTALL_SERVICE=0; shift ;;
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    --rebuild) REBUILD=1; shift ;;
    --yes|-y) shift ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

[[ "$STEP" =~ ^[1-9]$ ]] \
  || die "--step must be 1-9 (got '$STEP'). Step 10 is never a boot default."

detect_os() {
  if [[ -f /etc/NIXOS ]] || grep -qi '^ID=nixos' /etc/os-release 2>/dev/null; then
    echo nixos
  elif [[ -f /etc/alpine-release ]]; then
    echo alpine
  elif grep -qiE '^(ID|ID_LIKE)=.*(debian|ubuntu)' /etc/os-release 2>/dev/null; then
    echo debian
  else
    echo unknown
  fi
}

detect_init() {
  if have systemctl && [[ -d /run/systemd/system ]]; then
    echo systemd
  elif have rc-update || [[ -d /etc/init.d ]]; then
    echo openrc
  else
    echo none
  fi
}

OS="$(detect_os)"
INIT="$(detect_init)"
BIN="$PREFIX/tdp"
SHARE="/usr/local/share/tdp"

w "os=$OS  init=$INIT  prefix=$PREFIX  step=$STEP"

fetch() {
  local url=$1 dest=$2
  if have curl; then curl -fsSL "$url" -o "$dest"
  elif have wget; then wget -qO "$dest" "$url"
  else die "need curl or wget"
  fi
}

# Resolve a local checkout of tdp when not running via curl|bash.
local_tdp() {
  local candidates=()
  if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "bash" ]]; then
    local d
    d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
    [[ -n "$d" ]] && candidates+=("$d/tdp")
  fi
  candidates+=("./tdp" "/docker/tdp/tdp")
  local c
  for c in "${candidates[@]}"; do
    [[ -f "$c" ]] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

do_uninstall() {
  need_root
  w "removing tdp…"
  rm -f "$BIN"
  rm -rf "$SHARE"
  if [[ "$INIT" == "systemd" ]]; then
    systemctl disable --now "$UNIT_NAME.service" 2>/dev/null || true
    rm -f "/etc/systemd/system/${UNIT_NAME}.service"
    systemctl daemon-reload 2>/dev/null || true
  elif [[ "$INIT" == "openrc" ]]; then
    rc-update del "$UNIT_NAME" default 2>/dev/null || true
    rm -f "/etc/init.d/${UNIT_NAME}"
  fi
  if [[ -f /etc/nixos/tdp.nix ]]; then
    w "note: /etc/nixos/tdp.nix left in place — drop its import from configuration.nix if you added one"
  fi
  w "✔ uninstalled"
  exit 0
}

[[ "$UNINSTALL" == "1" ]] && do_uninstall
need_root

# ---- ryzenadj -------------------------------------------------------------
ensure_path_ryzenadj() {
  # nix profile installs land here; make them visible in this script.
  export PATH="/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:${PATH}"
}

install_ryzenadj() {
  ensure_path_ryzenadj
  if have ryzenadj; then
    w "ryzenadj already on PATH: $(command -v ryzenadj)"
    return 0
  fi

  case "$OS" in
    nixos)
      have nix || die "nix not found"
      w "installing ryzenadj via nix…"
      if nix --extra-experimental-features 'nix-command flakes' profile install 'nixpkgs#ryzenadj' 2>/dev/null; then
        :
      elif nix-env -iA nixpkgs.ryzenadj 2>/dev/null; then
        :
      else
        die "could not install ryzenadj via nix"
      fi
      ensure_path_ryzenadj
      ;;
    debian)
      w "building ryzenadj from source (apt deps)…"
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y -qq build-essential cmake libpci-dev pkg-config git >/dev/null
      build_ryzenadj
      ;;
    alpine)
      w "building ryzenadj from source (apk deps)…"
      apk add --no-cache build-base cmake pciutils-dev pkgconf git linux-headers >/dev/null
      build_ryzenadj
      ;;
    *)
      die "unsupported OS '$OS' — install ryzenadj yourself, then re-run"
      ;;
  esac

  ensure_path_ryzenadj
  have ryzenadj || die "ryzenadj still not on PATH after install"
  w "✔ ryzenadj → $(command -v ryzenadj)"
}

build_ryzenadj() {
  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  git clone --depth 1 "$RYZENADJ_GIT" "$tmp/RyzenAdj" >/dev/null 2>&1
  cmake -S "$tmp/RyzenAdj" -B "$tmp/RyzenAdj/build" -DCMAKE_BUILD_TYPE=Release >/dev/null
  cmake --build "$tmp/RyzenAdj/build" -j"$(nproc 2>/dev/null || echo 2)" >/dev/null
  install -Dm755 "$tmp/RyzenAdj/build/ryzenadj" /usr/local/bin/ryzenadj
}

# ---- tdp binary -----------------------------------------------------------
install_binary() {
  mkdir -p "$PREFIX" "$SHARE"
  local src tmp
  tmp="$(mktemp)"
  if src="$(local_tdp)"; then
    w "using local checkout: $src"
    cp "$src" "$tmp"
  else
    w "fetching $REPO_RAW/tdp"
    fetch "$REPO_RAW/tdp" "$tmp"
  fi
  install -Dm755 "$tmp" "$BIN"
  install -Dm644 "$tmp" "$SHARE/tdp"   # kept for the NixOS module to read
  rm -f "$tmp"
  w "✔ installed $BIN"
}

# ---- boot units -----------------------------------------------------------
install_systemd() {
  local unit="/etc/systemd/system/${UNIT_NAME}.service"
  local ry
  ry="$(command -v ryzenadj)"
  cat >"$unit" <<EOF
[Unit]
Description=Set Strix Halo TDP ladder step at boot (tdp)
Documentation=https://github.com/HariantoAtWork/tdp
After=multi-user.target
ConditionPathExists=$BIN

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$BIN set $STEP
Environment=TDP_RYZENADJ=$ry

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "$UNIT_NAME.service"
  w "✔ systemd ${UNIT_NAME}.service enabled (boot → step $STEP)"
}

install_openrc() {
  local init="/etc/init.d/${UNIT_NAME}"
  local ry
  ry="$(command -v ryzenadj)"
  cat >"$init" <<EOF
#!/sbin/openrc-run
description="Set Strix Halo TDP ladder step at boot (tdp)"

depend() {
  after localmount
}

start() {
  ebegin "Setting TDP to step $STEP"
  TDP_RYZENADJ="$ry" "$BIN" set "$STEP"
  eend \$?
}
EOF
  chmod +x "$init"
  rc-update add "$UNIT_NAME" default >/dev/null
  "$init" start || true
  w "✔ openrc ${UNIT_NAME} enabled (boot → step $STEP)"
}

# NixOS: /etc/systemd/system is a read-only symlink into the store, so boot
# persistence MUST go through a declarative module under /etc/nixos/.
install_nixos_module() {
  local mod="/etc/nixos/tdp.nix"
  cat >"$mod" <<EOF
# Generated by tdp install.sh — do not edit by hand (re-run installer to refresh).
# Wired into configuration.nix via:  imports = [ ./tdp.nix ];
{ pkgs, ... }:
let
  tdpPkg = pkgs.writeShellApplication {
    name = "tdp";
    runtimeInputs = [ pkgs.ryzenadj pkgs.gawk pkgs.coreutils pkgs.gnugrep pkgs.gnused ];
    text = builtins.readFile $SHARE/tdp;
  };
in
{
  environment.systemPackages = [ tdpPkg pkgs.ryzenadj ];

  systemd.services.tdp = {
    description = "Set Strix Halo TDP ladder step at boot";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Safe range only (1-9). Interactive override: tdp set 10 --force
      ExecStart = "\${tdpPkg}/bin/tdp set $STEP";
    };
  };
}
EOF
  w "✔ wrote $mod"

  local cfg="/etc/nixos/configuration.nix"
  if [[ ! -f "$cfg" ]]; then
    w "no $cfg found — add the module manually when you have one"
    return 0
  fi

  if grep -qE 'tdp\.nix' "$cfg" 2>/dev/null; then
    w "configuration.nix already imports tdp.nix"
  elif [[ "$REBUILD" == "1" ]]; then
    if grep -qE 'imports\s*=\s*\[' "$cfg"; then
      # Backup once, then insert into the imports list.
      [[ -f "${cfg}.bak-before-tdp" ]] || cp "$cfg" "${cfg}.bak-before-tdp"
      sed -i '/imports\s*=\s*\[/a\    ./tdp.nix' "$cfg"
      w "✔ added ./tdp.nix to imports in $cfg (backup: ${cfg}.bak-before-tdp)"
    else
      die "could not find an imports = [ ... ] block in $cfg — add ./tdp.nix manually"
    fi
  else
    w "next: add to $cfg →  imports = [ ./tdp.nix ];"
  fi

  if [[ "$REBUILD" == "1" ]]; then
    w "running nixos-rebuild switch…"
    nixos-rebuild switch
    w "✔ nixos-rebuild finished — boot service is active"
  else
    w "boot service needs a rebuild on NixOS:"
    w "  sudo bash install.sh --rebuild"
    w "  # or: edit imports, then sudo nixos-rebuild switch"
  fi
}

# ---- main -----------------------------------------------------------------
install_ryzenadj
install_binary

w "applying step $STEP now…"
ensure_path_ryzenadj
TDP_RYZENADJ="$(command -v ryzenadj)" "$BIN" set "$STEP" \
  || w "warn: live apply failed (SMU?). Boot unit will retry."

if [[ "$INSTALL_SERVICE" == "1" ]]; then
  if [[ "$OS" == "nixos" ]]; then
    # Imperative systemd units cannot be written on NixOS (/etc/systemd → store).
    install_nixos_module
  else
    case "$INIT" in
      systemd) install_systemd ;;
      openrc)  install_openrc ;;
      none)    w "no systemd/openrc — skipped boot service" ;;
    esac
  fi
else
  w "skipped boot service (--no-service)"
fi

echo
w "✔ done"
w "  binary : $BIN"
w "  try    : tdp show"
w "  raise  : tdp set 7"
w "  ceiling: tdp set 10 --force"
echo
