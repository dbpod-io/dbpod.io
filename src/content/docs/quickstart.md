---
title: Quickstart
description: Install dbpod, start your first instance, run SQL, stop and clean up.
order: 1
---

## Install

One command, no root, no system services:

```bash
curl -fsSL https://dbpod.io/install.sh | sh
```

On Windows (PowerShell):

```powershell
irm https://dbpod.io/install.ps1 | iex
```

Or plain cmd, no PowerShell needed (curl and tar are bundled with Windows 10+):

```bat
curl -fsSL https://dbpod.io/install.bat -o "%TEMP%\dbpod-install.bat" && call "%TEMP%\dbpod-install.bat"
```

The script detects your platform (macOS, Linux, or Windows) and downloads the matching single
binary from [GitHub Releases](https://github.com/dbpod-io/dbpod/releases), verifying it against
the published checksums. Verify it:

```bash
dbpod version
```

### One-shot install with a database

To install the CLI and a database engine in a single command, pass `--engine`:

```bash
curl -fsSL https://dbpod.io/install.sh | sh -s -- --engine mysql@8.0
```

This installs dbpod, then immediately runs `dbpod engine install mysql@8.0` for you — the
engine is cached and ready before you type anything else. Repeat `--engine` (or use
`DBPOD_ENGINES="mysql@8.0 postgres@17"`) for multiple engines:

```bash
curl -fsSL https://dbpod.io/install.sh | sh -s -- --engine mysql@8.0 --engine postgres@17
```

The same works from cmd:

```bat
curl -fsSL https://dbpod.io/install.bat -o "%TEMP%\dbpod-install.bat" && call "%TEMP%\dbpod-install.bat" --engine mysql@8.0
```

Other options: `--version vX.Y.Z` pins the CLI version, `--install-dir` overrides the install
location (default `~/.local/bin`). See all of them with `sh -s -- --help`. Prefer a guided
setup? The [install builder](/install/) generates the one-shot command for your platform and
engines.

## Install an engine

Engines are handled like Docker images — you pick a series, dbpod resolves the exact version:

```bash
dbpod engine install mysql@8.0
```

```text
✓ resolved mysql@8.0 → 8.0.46
✓ installed → ~/.dbpod/versions/mysql/8.0.46
```

The series notation `mysql@8.0` resolves to the latest known patch release (here `8.0.46`).
The engine binaries are cached under `DBPOD_HOME/versions` and reused across projects.

## Run your first instance

```bash
dbpod run --name dev --engine mysql@8.0
```

```text
✓ dev is ready → 127.0.0.1:3306 · datadir ./.dbpod/dev
```

The command returns as soon as the server is ready to accept connections — the instance keeps
running in the background, detached. All state (data, logs, socket, pid) lives inside the
project's `./.dbpod/` directory. Nothing leaks into system paths.

## Run some SQL

`exec` drops you into the engine's SQL shell with the instance target pre-connected:

```bash
dbpod exec dev
```

```sql
SELECT VERSION();
```

Or run a one-shot statement without opening a shell:

```bash
dbpod exec dev -e "SELECT 1"
```

## Inspect, stop, clean up

```bash
dbpod ps          # instances in this project
dbpod stop dev    # graceful shutdown
dbpod rm dev      # remove the instance
```

Because the datadir is project-local, deleting `./.dbpod/` removes the database completely.
That is the whole story: the host stays clean, and every project owns its data.

## Next steps

- [Engines](/docs/engines/) — series resolution, LTS/innovation, `engine ls` views
- [Instances](/docs/instances/) — lifecycle, ports, monitors
- [Exec](/docs/exec/) — the distribution as a toolbox
