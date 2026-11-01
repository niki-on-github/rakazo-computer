# rakazo-computer

The [Rakazo](https://github.com/elie222/rakazo) computer image (the per-bot desktop pod) with **Nix (flakes)** and
**Apptainer** added, so bots can run `nix run`, `nix shell`, `nix develop`, `nix build` and rootless containers
without root.

Layered on the official image `ghcr.io/elie222/rakazo/computer`, so the desktop, screen and terminal helpers stay
upstream's. **Keep the base tag equal to the Rakazo app tag you deploy**: those helpers are versioned with the app.

## Image

| Tag | Meaning |
|---|---|
| `ghcr.io/niki-on-github/rakazo-computer:<base-tag>` | e.g. `v0.3.6`. Moves with every rebuild of this repo; pin it by digest. |
| `ghcr.io/niki-on-github/rakazo-computer:<base-tag>-<sha7>` | Immutable, one per commit. |
| `ghcr.io/niki-on-github/rakazo-computer:latest` | Newest build. |

amd64 only. Each push job prints the pinned reference (`<tag>@sha256:…`) in its summary.

Use it in Rakazo:

```yaml
KUBERNETES_SANDBOX_COMPUTER_IMAGE: ghcr.io/niki-on-github/rakazo-computer:v0.3.6@sha256:<digest>
```

then use the computer's **Update** action to recreate the pod.

## What is added

| Component | How | Notes |
|---|---|---|
| Nix | `/nix` copied from `nixos/nix`, owned by uid 1000 | Single-user, no daemon, `sandbox = false`, flakes on. On `PATH` (after the Debian tools) for exec and login shells. |
| Apptainer | upstream non-suid `.deb`, sha256 pinned | Unprivileged user-namespace mode. The `uidmap` it pulls in is stripped of setuid, so mapping is single-uid. |

Nothing else changes: `USER 1000:1000`, `CMD`, `HOME=/home/rakazo`, `DISPLAY` and the nss_wrapper env come from the base.

### Nix

- `/nix` is in the container layer: it is **lost when the pod is recreated** (Update). Use `nix run`, `nix shell`,
  `nix develop`; avoid `nix profile install` (the profile lives in the persistent home and would point at missing
  store paths after an Update).
- A cache proxy can be added at runtime without rebuilding, either through the environment
  (`NIX_CONFIG`, e.g. injected by an admission policy) or per bot in `~/.config/nix/nix.conf`:

  ```
  extra-substituters = https://cache.example
  extra-trusted-public-keys = cache.example:AAAA…
  ```

  No private cache is baked in: this image is public.

### Apptainer

```sh
apptainer exec docker://alpine:3 cat /etc/alpine-release
apptainer exec --nv docker://nvidia/cuda:<tag> nvidia-smi   # only if the pod has a GPU
```

The pod's masked `/proc` does not allow a fresh `/proc` mount, so `apptainer.conf` sets `mount proc = no` and
`bind path = /proc`: containers see the pod's `/proc`. Do not use `--pid` / `--containall`. The pod has no
`/dev/fuse`, so the image sets `APPTAINER_UNSQUASH=true`: SIF images are unpacked to a temporary sandbox in `/tmp`
instead of being mounted with squashfuse. The image cache is `~/.apptainer/cache` (persistent home).

## Build

`.github/workflows/build.yml`, on push to `main` and manual runs (no pull request builds):

1. builds the image (`linux/amd64`, GitHub Actions cache),
2. runs `tests/smoke.sh` inside it as uid 1000 with an empty home, no seccomp filter (like the pod): Nix flakes
   (`nix run nixpkgs#hello`), `NIX_CONFIG`, Apptainer (`docker://alpine`), no setuid in the added tools, base tools
   still present,
3. pushes to GHCR only if the smoke test passed.

Local build:

```sh
docker build -t rakazo-computer:dev .
docker run --rm --user 1000:1000 --security-opt seccomp=unconfined \
  --tmpfs /home/rakazo:uid=1000,gid=1000,exec -v "$PWD/tests:/tests:ro" rakazo-computer:dev env -u LD_PRELOAD /tests/smoke.sh
```

## Updates

Renovate (`renovate.json`) pins and bumps the base image, `nixos/nix`, the Apptainer release (version and sha256 of
the `.deb`) and the GitHub Actions. All updates, majors included, are committed straight to `main` (branch automerge, no PR,
`ignoreTests` because no checks run on Renovate branches); that push builds, tests and publishes. A failing update
does not replace the published tags: fix or revert it on `main`.
Requires the [Renovate GitHub App](https://github.com/apps/renovate) on this repo and no branch protection that blocks
its pushes to `main`. A new Rakazo base tag publishes a new image tag (e.g. `v0.3.7`): move the app and this image
together in the deployment.

Manual bump: change the tag and digest in `FROM ghcr.io/elie222/rakazo/computer:…` (`crane digest <ref>`), or
`APPTAINER_VERSION` + `APPTAINER_SHA256` (`sha256sum` of the release `.deb`).
