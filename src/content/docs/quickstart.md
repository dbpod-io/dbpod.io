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

The script detects your platform (macOS, Linux, or Windows) and downloads the matching single
binary from [GitHub Releases](https://github.com/dbpod-io/dbpod/releases). Verify it:

```bash
dbpod --version
```

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
