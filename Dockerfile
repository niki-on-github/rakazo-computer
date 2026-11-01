# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
# hadolint global ignore=DL3008,DL4006
# Rakazo computer image with Nix (flakes) and Apptainer, layered on the upstream
# computer image. Keep the base tag equal to the Rakazo app tag you deploy: the
# screen/terminal helpers in the base are versioned with the app.

# Nix: the official image ships a complete single-user store in /nix.
FROM docker.io/nixos/nix:2.35.4@sha256:f159a58f390677f41e8e900a74b6e2f9c7f27b364122ae6acf7a652ce6c551c0 AS nix

FROM ghcr.io/elie222/rakazo/computer:v0.3.6@sha256:3b821e1a0074bd05b62d5b3d1422480074d98aad4102b7e1072f4fe38721c3bb

USER root

# Apptainer (non-suid build) for rootless containers. The package pulls in
# uidmap; its setuid bits are removed below, so Apptainer runs in plain
# unprivileged user-namespace mode (single uid mapping).
# Every RUN unsets LD_PRELOAD: the base's nss_wrapper needs passwd/group files
# that only start.sh creates, so user lookups fail at build time.
ARG APPTAINER_VERSION=v1.5.5
ARG APPTAINER_SHA256=25095d3711504b3e8657dbb2e172ef8db9db43c4503d940c9c36b105db8dce77
RUN set -eux; \
  unset LD_PRELOAD; \
  deb="/tmp/apptainer_${APPTAINER_VERSION#v}_amd64.deb"; \
  curl -fsSL -o "$deb" "https://github.com/apptainer/apptainer/releases/download/${APPTAINER_VERSION}/apptainer_${APPTAINER_VERSION#v}_amd64.deb"; \
  echo "${APPTAINER_SHA256}  $deb" | sha256sum -c -; \
  apt-get update; \
  apt-get install -y --no-install-recommends "$deb"; \
  rm -rf /var/lib/apt/lists/* "$deb"; \
  chmod u-s,g-s /usr/bin/newuidmap /usr/bin/newgidmap; \
  # The pod masks parts of /proc, so a fresh proc mount is refused (also for the
  # unsquashfs helper container). Bind the existing /proc instead; that works.
  sed -i -e 's/^mount proc = yes$/mount proc = no/' /etc/apptainer/apptainer.conf; \
  printf '%s\n' 'bind path = /proc' >> /etc/apptainer/apptainer.conf; \
  # NixOS nodes: the NVIDIA runtime mounts the driver and its glibc under /nix/store, and --nv
  # copies NixOS-built binaries (nvidia-smi) that need them. Bind the store into containers.
  printf '%s\n' 'bind path = /nix/store' >> /etc/apptainer/apptainer.conf; \
  grep -qx 'mount proc = no' /etc/apptainer/apptainer.conf; \
  install -d -m 755 /etc/nix /usr/share/doc/rakazo-computer

# Nix: /nix owned by uid 1000 so the bot uses it without root or a daemon.
COPY --from=nix --chown=1000:1000 /nix /nix
# /etc/nix is created above with 755: COPY --chmod would give a directory it
# creates 644, and uid 1000 could not read the config (Nix ignores it silently).
COPY --chmod=644 rootfs/etc/nix/nix.conf /etc/nix/nix.conf
# Usage guide for the bots (their instructions point here).
COPY --chmod=644 rootfs/usr/share/doc/rakazo-computer/GUIDE.md /usr/share/doc/rakazo-computer/GUIDE.md
# Login shells reset PATH in /etc/profile; this puts Nix back.
COPY --chmod=644 rootfs/etc/profile.d/nix.sh /etc/profile.d/nix.sh
# Appended, not prepended: Debian's tools stay first, Nix only adds `nix` & co.
ENV PATH=${PATH}:/nix/var/nix/profiles/default/bin

# No /dev/fuse in the pod: unpack SIF images to a temporary sandbox instead of
# mounting them with the bundled squashfuse (same as `apptainer exec --unsquash`).
ENV APPTAINER_UNSQUASH=true
# The base's nss_wrapper preload does not exist inside containers; do not pass it in.
ENV APPTAINERENV_LD_PRELOAD=

# Report what can still gain privileges (the pod does not set no_new_privs).
RUN unset LD_PRELOAD; echo "setuid/setgid files:"; find / -xdev -perm /6000 -type f -print 2>/dev/null || true

USER 1000:1000
# Separate steps so a failure names the tool. Run as the bot user;
# tests/smoke.sh covers the real runtime environment (with nss_wrapper).
RUN unset LD_PRELOAD; apptainer --version
RUN set -eux; \
  unset LD_PRELOAD; \
  HOME="$(mktemp -d)"; export HOME; \
  nix --version; \
  ls -ld /etc/nix /etc/nix/nix.conf; \
  test -r /etc/nix/nix.conf; \
  nix config show experimental-features | grep -q flakes; \
  nix eval --expr '1 + 1'; \
  nix flake --help >/dev/null; \
  rm -rf "$HOME"

LABEL org.opencontainers.image.title="rakazo-computer" \
      org.opencontainers.image.description="Rakazo computer image with Nix (flakes) and Apptainer"
# CMD, ENTRYPOINT, HOME, DISPLAY and the nss_wrapper env are inherited from the base.
