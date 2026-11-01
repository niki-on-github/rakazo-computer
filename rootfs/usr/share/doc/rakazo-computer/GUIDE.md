# Your computer: how to use it

Read this before you install software, use Nix, run containers or use the GPU.

## The shell tool refuses some commands

Your shell tool has a desktop-protection guard. It refuses commands with `$(...)`, backticks, `$((...))`,
heredocs (`<<EOF`), some `$VAR` expansions, and `kill` / `pkill` / `killall`. A refusal is not a permission
error. Rewrite the command without these constructs (for example, use literal values), and do not try to get
around the guard. Never stop or restart the browser or desktop processes.

## The basics

- Debian 12 desktop. You are `rakazo` (uid 1000). There is **no root and no sudo**: `apt install` and
  writing to system paths do not work. Do not try to work around this.
- **Only `/home/rakazo` is kept.** Everything else (`/tmp`, `/nix`, anything installed outside the home) is lost
  when the computer is updated or recreated. Put work you want to keep in the home.
- The home is on a disk shared with other bots. Keep it small and clean up caches you no longer need (see "Disk").
- Limits: 2 CPU, 32 GiB RAM. The machine and its RAM are shared with other services; avoid large builds
  and huge downloads.
- Network: the internet is reachable. Private and LAN addresses are blocked, except the local caches (Nix, PyPI,
  Hugging Face) and the LLM gateway.
- Never store secrets (tokens, passwords, keys) in files in the home.

## Already installed

python3, uv / uvx, git, gh, curl, jq, unzip, pandoc, poppler-utils (pdftotext, pdfinfo), ImageMagick,
Chromium, xdotool, ssh client, **nix** (with flakes) and **apptainer**.

## Getting other tools: use Nix

Nix gives you almost any package without root. Packages come prebuilt from a fast local cache.

```sh
nix shell nixpkgs#ffmpeg nixpkgs#ripgrep    # a shell with these tools on PATH
nix shell nixpkgs#ffmpeg -c ffmpeg -version  # run one command with a tool
nix run nixpkgs#cowsay -- hello              # run a package's main program
nix search nixpkgs ffmpeg                    # find package names (slow; prefer search.nixos.org)
```

For a project, write a `flake.nix` with a dev shell in the project directory and use `nix develop`; it pins the
toolchain and can be recreated at any time.

Rules:

- **Do not use `nix profile install` or `nix-env -i`.** The installed programs live in `/nix`, which is lost on the
  next update, while the profile in the home would keep pointing at them. Use `nix shell` / `nix run` /
  `nix develop` instead; they are fast because of the cache.
- `./result` links from `nix build` also break after an update. Rebuild them when needed.
- Do not change `substituters` or the cache settings; the Nix cache is already configured. To add an extra cache,
  put `extra-substituters` and `extra-trusted-public-keys` in `~/.config/nix/nix.conf`.
- Builds run without the Nix build sandbox. Prefer packages that come from the cache over building from source.
- Unfree packages (CUDA and others): `NIXPKGS_ALLOW_UNFREE=1 nix shell --impure nixpkgs#<pkg>`.

## Python packages

pip and uv already use a local PyPI mirror (`PIP_INDEX_URL`, `UV_DEFAULT_INDEX`); do not override the index.

## Hugging Face models

Hugging Face downloads (`huggingface_hub`, `transformers`, `hf download`) go through a local cache
(`HF_ENDPOINT`); do not override it. Downloads are stored in `~/.cache/huggingface` on the shared home disk:
fetch only what you need and delete models you are done with. There is no Hugging Face token; gated or private
models are not available.

Other ways that keep working across updates (they install into the home):

- Python tools: `uv tool install <pkg>` (puts commands in `~/.local/bin`) or `uvx <pkg>` for one run.
- Python projects: `uv venv` / `uv pip install` / `uv run` inside the project directory.
- Single static binaries: download into `~/.local/bin`.

## Containers: Apptainer

Docker and Podman are not available. Apptainer runs container images without root:

```sh
apptainer exec docker://python:3.13-slim python3 -c 'print("hi")'
apptainer shell docker://alpine:3
apptainer exec --nv docker://nvidia/cuda:12.9.1-base-ubuntu24.04 nvidia-smi   # with the GPU
```

- Containers share your network, your `/proc` and your home (`/home/rakazo` is mounted inside).
- Images are unpacked to `/tmp` on each run (slower startup), and downloaded images are cached in
  `~/.apptainer/cache`. Clean it with `apptainer cache clean -f`.
- Not available: `--pid`, `--containall`, `--fakeroot`, `--net`, building images that need root.
- Prefer Nix for single tools; use Apptainer when you need a specific image or distribution.

## GPU

There is one NVIDIA RTX 3090 (24 GB). Check it with `nvidia-smi`.

- It is **shared** with other services (an LLM server) and other bots. Check free memory with `nvidia-smi` before
  starting GPU work, keep usage small and stop GPU processes when you are done.
- The driver is provided; there is no CUDA toolkit in the image. Easiest options:
  - PyTorch and similar via uv/pip: their wheels include the CUDA libraries
    (`uv venv && uv pip install torch`).
  - A CUDA container: `apptainer exec --nv docker://nvidia/cuda:<tag> ...`.
- CUDA programs built with Nix may not find the driver library; prefer the two options above.
- `nvidia/cuda:*-base-*` images have no Python; use a `runtime` or `devel` image, or install what you need.

## Disk

Check usage with `du -sh ~/.cache ~/.apptainer ~/.local 2>/dev/null` and clean what you do not need:

```sh
uv cache clean
apptainer cache clean -f
nix store gc            # frees /nix (lost on update anyway)
```

## When something does not work

Report the exact command and error. Do not try to gain root, change system files or bypass the network rules.
