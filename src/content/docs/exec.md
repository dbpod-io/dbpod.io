---
title: Exec
description: Every binary in the distribution, one command away — SQL shells, client tools, and engine-local executables.
order: 4
---

## The idea

Every engine distribution ships not just a server but a whole toolbox: `mysql`, `psql`,
`mysqldump`, `pg_dump`, and friends. dbpod's `exec` gives you all of them, version-matched to
your engine, without installing anything globally.

Three forms, one command:

## 1. Open a SQL shell on an instance

```bash
dbpod exec dev
```

Opens the engine's SQL shell (e.g. `mysql` for a MySQL instance) with the instance target
**pre-connected** — no host/port/password juggling. The shell, server, and protocol version
always match because they come from the same distribution.

## 2. Run any binary from the distribution

```bash
dbpod exec dev mysqldump --help
dbpod exec dev mysqldump -h 127.0.0.1 dev > backup.sql
```

The first argument after the instance name is the binary; everything after is passed through
verbatim. This works for **any executable in the distribution**, not a hardcoded whitelist.

## 3. Use a distribution without an instance

```bash
dbpod exec mysql@8.0.46 mysql --version
```

Target an **engine version** instead of an instance and you get a one-shot client from that
distribution — handy for connecting to remote servers with a specific client version, or
checking tool availability without starting anything.

## exec paths

`exec` injects the distribution's binary directories into `PATH` before running your command.
That means:

- Scripts executed via `exec` can call sibling tools directly.
- Wrapper scripts and engines that shell out to their own utilities keep working.

## Why this matters

Version skew between client and server is a classic production headache (mismatched dumps,
incompatible flags). With dbpod, the client tooling is the same distribution as the server —
by construction, not by discipline.
