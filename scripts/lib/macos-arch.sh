# shellcheck shell=bash
#
# macos-arch.sh - host/target CPU architecture helpers shared by the macOS
# build, bundle and verification scripts. Source it; it defines functions only.
#
# ClassicMac builds one architecture per build tree: arm64 (Apple Silicon) or
# x86_64 (Intel). CLASSICMAC_ARCH selects it and defaults to the architecture
# of the running process, so a plain build is native exactly as before. On an
# Apple Silicon Mac with Rosetta 2 and an Intel Homebrew in /usr/local,
# CLASSICMAC_ARCH=x86_64 re-runs the script under Rosetta and produces native
# x86_64 binaries. scripts/make-universal-app.sh merges an arm64 and an x86_64
# ClassicMac.app into one universal app.

classicmac_arch_die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

# Architecture of the running process (x86_64 under Rosetta 2).
classicmac_host_arch() {
  local machine
  machine="$(uname -m)"
  case "$machine" in
    arm64|aarch64) printf 'arm64\n' ;;
    x86_64|amd64) printf 'x86_64\n' ;;
    *) printf '%s\n' "$machine" ;;
  esac
}

classicmac_validate_arch() {
  case "$1" in
    arm64|x86_64) ;;
    *) classicmac_arch_die "Unsupported macOS architecture '$1' (expected arm64 or x86_64)" ;;
  esac
}

# CLASSICMAC_ARCH, defaulting to the running process's architecture.
classicmac_target_arch() {
  local arch="${CLASSICMAC_ARCH:-$(classicmac_host_arch)}"
  classicmac_validate_arch "$arch"
  printf '%s\n' "$arch"
}

# Homebrew's default (and only bottle-compatible) prefix for an architecture.
# CLASSICMAC_HOMEBREW_PREFIX overrides it.
classicmac_homebrew_prefix() {
  if [ -n "${CLASSICMAC_HOMEBREW_PREFIX:-}" ]; then
    printf '%s\n' "$CLASSICMAC_HOMEBREW_PREFIX"
    return
  fi
  case "$1" in
    arm64) printf '/opt/homebrew\n' ;;
    x86_64) printf '/usr/local\n' ;;
    *) classicmac_arch_die "No Homebrew prefix for architecture '$1'" ;;
  esac
}

# Usage: classicmac_run_as_arch ARCH SCRIPT [ARGS...]
# Returns when this process already runs as ARCH; otherwise re-executes SCRIPT
# under arch(1) (Rosetta 2 for x86_64 on Apple Silicon) and never returns.
classicmac_run_as_arch() {
  local arch="$1"
  shift
  [ "$(classicmac_host_arch)" != "$arch" ] || return 0
  [ -z "${CLASSICMAC_ARCH_REEXEC:-}" ] || \
    classicmac_arch_die "Could not switch this build to $arch (still running as $(classicmac_host_arch))"
  if ! /usr/bin/arch "-$arch" /usr/bin/true >/dev/null 2>&1; then
    if [ "$arch" = x86_64 ]; then
      classicmac_arch_die "This Mac cannot run x86_64 code. Install Rosetta 2 (softwareupdate --install-rosetta) or build x86_64 on an Intel Mac, then merge with scripts/make-universal-app.sh."
    fi
    classicmac_arch_die "This Mac cannot run $arch code. Build $arch on an Apple Silicon Mac, then merge with scripts/make-universal-app.sh."
  fi
  printf '\n==> Re-running %s as %s\n' "$(basename "$1")" "$arch"
  CLASSICMAC_ARCH="$arch" CLASSICMAC_ARCH_REEXEC=1 exec /usr/bin/arch "-$arch" /bin/bash "$@"
}

# Usage: classicmac_require_archs FILE ARCH...
# Fails unless FILE is a Mach-O whose architectures are exactly ARCH...
classicmac_require_archs() {
  local file="$1"
  shift
  local expected actual
  expected="$(printf '%s\n' "$@" | sort | tr '\n' ' ')"
  actual="$(lipo -archs "$file" 2>/dev/null | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ')" || true
  [ "$actual" = "$expected" ] || \
    classicmac_arch_die "$(basename "$file") is built for '${actual% }', expected '${expected% }'"
}
