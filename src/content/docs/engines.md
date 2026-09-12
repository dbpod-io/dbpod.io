---
title: Engines
description: Install, inspect, and remove database engines — series resolution, LTS and innovation tracks, version cache.
order: 2
---

## Concept

An **engine** is an installed database distribution — the analogue of a Docker image. Engines
are versioned, cached once under `DBPOD_HOME/versions`, and shared by every project on the
machine. Instances (the analogue of containers) are created from engines.

## Install

```bash
dbpod engine install mysql@8.0
```

### Series resolution

You normally reference an engine by **series** (`mysql@8.0`), not by full version. Resolution
rules:

1. If a suitable version of the series already exists locally, it is reused.
2. Otherwise the series resolves to the latest known patch release — e.g. `mysql@8.0` →
   `8.0.46`.

The version index is generated offline and shipped with dbpod, so resolution never crawls the
web at runtime. When a new patch lands upstream, refresh the local metadata:

```bash
dbpod registry update
```

You can always pin the exact version if you want reproducibility:

```bash
dbpod engine install mysql@8.0.46
```

## List

`engine ls` supports four views:

```bash
dbpod engine ls                # installed engines
dbpod engine ls --all          # everything the index knows about
dbpod engine ls --lts          # LTS releases only
dbpod engine ls --series       # grouped by series, latest patch per series
```

LTS and innovation releases are grouped correctly — for engines that follow calendar
versioning, innovation releases are tracked separately from LTS lines, so you can pick a
stable baseline or follow the frontier.

## Remove

```bash
dbpod engine rm mysql@8.0.46
```

Removing an engine only deletes the cached binaries from the version store. Instances created
from it are unaffected until they need to start again — data always lives in the instance's
project-local datadir, never inside the engine cache.

## Cross-platform by construction

- Binaries are built for **darwin, linux, and windows**; the installer picks the right one.
- All client-facing commands (exec, project exec) use pure TCP connections, so one engine
  manifest serves every platform — Windows instances work even though they have no unix
  socket.

## Which engines are available?

`mysql` and `postgres` are built in. Further engines (MariaDB, Percona Server, MongoDB, …)
come from the `dbpod-ext` registry — see [Registry](/docs/registry/) and
[Extend](/docs/extend/).
