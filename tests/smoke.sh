#!/usr/bin/env bash
# Runs inside the image as uid 1000 (see the workflow). Mirrors what a bot does:
# commands run with the image env (LD_PRELOAD nss_wrapper) and a fresh home.
set -euo pipefail
trap 'echo "FAIL: line $LINENO: $BASH_COMMAND" >&2' ERR

fail() { echo "FAIL: $*" >&2; exit 1; }
step() { echo "--- $*"; }

# start.sh writes these in a real computer pod; only create them in CI, where
# it never ran. nss_wrapper needs them for user lookups.
mkdir -p /tmp/rakazo-nss
[ -s /tmp/rakazo-nss/passwd ] || echo "rakazo:x:$(id -u):$(id -g)::$HOME:/bin/bash" > /tmp/rakazo-nss/passwd
[ -s /tmp/rakazo-nss/group ] || echo "rakazo:x:$(id -g):" > /tmp/rakazo-nss/group
# The workflow starts this script without the preload (the files did not exist
# yet); enable it now, like the base's user-env does once the files exist.
export LD_PRELOAD=/usr/local/lib/libnss_wrapper.so

step "identity"
[ "$(id -u)" = 1000 ] || fail "not uid 1000"
whoami || fail "whoami (nss_wrapper files?)"

step "no setuid in what this image adds"
for f in /usr/bin/newuidmap /usr/bin/newgidmap; do
  [ -u "$f" ] && fail "$f is setuid"
done

step "nix on PATH (exec and login shell)"
command -v nix || fail "nix not on PATH (not the rakazo-computer image?)"
bash -lc 'command -v nix' >/dev/null || fail "nix missing in a login shell"
[ -w /nix/store ] || fail "/nix/store not writable for uid 1000"

step "nix flakes"
nix --version || fail "nix --version"
nix eval --expr '1 + 1' || fail "nix eval (flakes/nix-command disabled?)"
nix flake metadata nixpkgs --json | head -c 200 || fail "nix flake metadata nixpkgs"
echo
nix run nixpkgs#hello || fail "nix run nixpkgs#hello"

step "NIX_CONFIG is honoured at runtime"
NIX_CONFIG='extra-substituters = https://example.invalid' nix config show substituters \
  | grep -q example.invalid || fail "NIX_CONFIG ignored"

step "apptainer"
apptainer --version || fail "apptainer not installed"
apptainer exec docker://docker.io/library/alpine:3 sh -c 'echo apptainer-ok; cat /etc/alpine-release' \
  || fail "apptainer exec docker://alpine"

step "bot guide"
[ -r /usr/share/doc/rakazo-computer/GUIDE.md ] || fail "GUIDE.md missing or unreadable"

step "base desktop tools still present"
for c in python3 Xvfb x11vnc fluxbox xdotool websockify git curl uv gh; do
  command -v "$c" >/dev/null || fail "missing $c"
done

echo "ALL OK"
