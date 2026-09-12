---
title: Project
description: Declare your whole database environment in dbpod.yaml and bring it up with one command — team-reproducible by default.
order: 5
---

## The idea

A hand-run instance is fine for scratch work, but real projects need an environment the whole
team reproduces identically. dbpod projects do with one file what docker-compose did for
services: **declare it, bring it up, share it.**

## dbpod.yaml

Commit a `dbpod.yaml` to your repository root:

```yaml
instances:
  - name: main
    engine: mysql@8.0
    port: 3306
    databases:
      - app
  - name: cache-db
    engine: postgres@17
    port: 5432
    databases:
      - app
```

The file declares engine series, instance names, ports, and the databases to create. Versions
resolve through the normal series rules, so `mysql@8.0` reproducibly maps to a concrete patch
on every machine.

## init and up

```bash
dbpod project init    # scaffold a dbpod.yaml from your current instances
dbpod project up      # create every instance declared in dbpod.yaml
```

`project init` is the fast path for existing work: it snapshots your running instances into a
`dbpod.yaml` you can commit.

`project up` is idempotent for teammates: instances that already exist are left alone,
missing ones are created. Anyone cloning the repo gets the full environment with one command.

## Init SQL

Declare `init` SQL files and they are imported automatically the first time an instance is
created:

```yaml
instances:
  - name: main
    engine: mysql@8.0
    databases:
      - app
    init:
      - ./schema/01_tables.sql
      - ./seed/dev_seed.sql
```

Schema and seed data become part of the repo — new contributors get a working database with
realistic data, not an empty shell.

## Instance operations through the project

```bash
dbpod project exec main     # SQL shell on the "main" instance
dbpod project logs main     # tail its logs
```

## Where the data lives

Exactly where single instances keep it: `./.dbpod/` in the project. Add the directory to
`.gitignore` (dbpod never commits data), and the environment is fully described by
`dbpod.yaml` + init SQL alone.
