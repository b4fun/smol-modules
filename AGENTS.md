# smol-modules

Drop-in modules that improve LLM-agent-based development workflows.

## Project structure

Each module lives in its own top-level directory (e.g. `modules/<name>/`). A module can be a binary, a bash script, or a Nix package — whatever fits the job.

## Conventions

- **Nix for dev environments.** Every module provides a `flake.nix` (or `shell.nix`) so contributors can enter a reproducible dev shell with `nix develop`.
- **One module, one concern.** Keep modules small and focused.
- **README per module.** Each module directory must contain a `README.md` explaining what it does, how to build/install it, and how an LLM agent should invoke it.
- **Root flake.** The top-level `flake.nix` composes all modules for convenience but each module must also work standalone.

## Adding a new module

1. Create `modules/<name>/`.
2. Add a `flake.nix` (or `shell.nix`) for the dev environment.
3. Add a `README.md`.
4. Wire it into the root `flake.nix` if applicable.

## Code style

- Shell scripts: use `set -euo pipefail`, pass ShellCheck.
- Go / Rust / other compiled languages: follow standard community formatting (`gofmt`, `rustfmt`, etc.).
- Keep dependencies minimal.
