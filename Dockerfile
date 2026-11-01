# syntax=docker/dockerfile:1
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
ARG APPTAINER_VERSION=v1.5.5
ARG APPTAINER_SHA256=25095d3711504b3e8657dbb2e172ef8db9db43c4503d940c9c36b105db8dce77
RUN set -eux; \
  deb="/tmp/apptainer_${APPTAINER_VERSION#v}_amd64.deb"; \
  curl -fsSL -o "$deb" "https://github.com/apptainer/apptainer/releases/download/${APPTAINER_VERSION}/apptainer_${APPTAINER_VERSION#v}_amd64.deb"; \
  echo "${APPTAINER_SHA256}  $deb" | sha256sum -c -; \
  apt-get update; \
  apt-get install -y --no-install-recommends "$deb"; \
  rm -rf /var/lib/apt/lists/* "$deb"; \
  chmod u-s,g-s /usr/bin/newuidmap /usr/bin/newgidmap

# Nix: /nix owned by uid 1000 so the bot uses it without root or a daemon.
COPY --from=nix --chown=1000:1000 /nix /nix
COPY --chmod=644 rootfs/etc/nix/nix.conf /etc/nix/nix.conf
# Login shells reset PATH in /etc/profile; this puts Nix back.
COPY --chmod=644 rootfs/etc/profile.d/nix.sh /etc/profile.d/nix.sh
# Appended, not prepended: Debian's tools stay first, Nix only adds `nix` & co.
ENV PATH=${PATH}:/nix/var/nix/profiles/default/bin

# Report what can still gain privileges (the pod does not set no_new_privs).
RUN echo "setuid/setgid files:"; find / -xdev -perm /6000 -type f -print 2>/dev/null || true

USER 1000:1000
# Separate steps so a failure names the tool. Run as the bot user. The base's
# nss_wrapper (LD_PRELOAD) needs files that only start.sh creates, so build-time
# checks run without it; tests/smoke.sh covers the real runtime environment.
RUN unset LD_PRELOAD; apptainer --version
RUN set -eux; \
  unset LD_PRELOAD; \
  HOME="$(mktemp -d)"; export HOME; \
  nix --version; \
  nix eval --expr '1 + 1'; \
  nix flake --help >/dev/null; \
  rm -rf "$HOME"

LABEL org.opencontainers.image.title="rakazo-computer" \
      org.opencontainers.image.description="Rakazo computer image with Nix (flakes) and Apptainer"
# CMD, ENTRYPOINT, HOME, DISPLAY and the nss_wrapper env are inherited from the base.
