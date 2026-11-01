#!/usr/bin/env bash
# Runs inside the image as uid 1000 (see the workflow). Mirrors what a bot does:
# commands run with the image env (LD_PRELOAD nss_wrapper) and a fresh home.
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
step() { echo "--- $*"; }

# start.sh normally writes these; nss_wrapper needs them for user lookups.
mkdir -p /tmp/rakazo-nss
echo "rakazo:x:$(id -u):$(id -g)::$HOME:/bin/bash" > /tmp/rakazo-nss/passwd
echo "rakazo:x:$(id -g):" > /tmp/rakazo-nss/group

step "identity"
[ "$(id -u)" = 1000 ] || fail "not uid 1000"
whoami

step "no setuid in what this image adds"
for f in /usr/bin/newuidmap /usr/bin/newgidmap; do
  [ -u "$f" ] && fail "$f is setuid"
done

step "nix on PATH (exec and login shell)"
command -v nix
bash -lc 'command -v nix' >/dev/null || fail "nix missing in a login shell"
[ -w /nix/store ] || fail "/nix/store not writable for uid 1000"

step "nix flakes"
nix --version
nix eval --expr '1 + 1'
nix flake metadata nixpkgs --json | head -c 200; echo
nix run nixpkgs#hello

step "NIX_CONFIG is honoured at runtime"
NIX_CONFIG='extra-substituters = https://example.invalid' nix config show extra-substituters \
  | grep -q example.invalid || fail "NIX_CONFIG ignored"

step "apptainer"
apptainer --version
apptainer exec docker://docker.io/library/alpine:3 sh -c 'echo apptainer-ok; cat /etc/alpine-release'

step "base desktop tools still present"
for c in python3 Xvfb x11vnc fluxbox xdotool websockify git curl uv gh; do
  command -v "$c" >/dev/null || fail "missing $c"
done

echo "ALL OK"
