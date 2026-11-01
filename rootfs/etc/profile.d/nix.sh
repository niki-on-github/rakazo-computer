# shellcheck shell=sh
# Nix default profile (single-user store in /nix, owned by the bot user).
case ":$PATH:" in
  *:/nix/var/nix/profiles/default/bin:*) ;;
  *) PATH="$PATH:/nix/var/nix/profiles/default/bin" ;;
esac
export PATH
