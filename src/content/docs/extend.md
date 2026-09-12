---
title: Extend
description: Add new engines with a single YAML manifest — lifecycle templates, families, and offline version indexes. No main-code changes.
order: 7
---

## The design bet

dbpod does not hardcode engines. The builtin `mysql` and `postgres` support use exactly the
same extension mechanism that is public to everyone else. That is why adding an engine —
MariaDB, Percona, MongoDB, anything — is **one YAML file**, not a pull request into dbpod's
source.

```bash
dbpod registry add ./mongodb.yaml   # a new engine, zero lines of main code changed
```

The community-maintained engines live in the [dbpod-ext](https://github.com/dbpod-io) repo —
each one is a manifest you can copy as a starting point for your own.

## The manifest

A manifest is a single YAML file that tells dbpod three things about an engine: **where to
download it**, **how to run its lifecycle**, and **which versions exist**.

```yaml
name: mariadb
family: mysql                     # shares client-tooling behavior with the mysql family
download:
  # where release archives come from, templated per version/platform/arch
  url: https://archive.mariadb.org/{version}/.../{platform}-{arch}.tar.gz
lifecycle:
  initdb: "{ datadir }/scripts/mysql-install-db --datadir={ datadir }"
  start: "{ bindir }/mysqld --datadir={ datadir } --port={ port } ..."
  stop:  "{ bindir }/mysqladmin -P { port } shutdown"
  # ...health, env, and other lifecycle hooks
```

### Template variables

Lifecycle commands are templates. dbpod substitutes variables such as:

| Variable       | Meaning                                  |
| -------------- | ---------------------------------------- |
| `{ datadir }`  | the instance's data directory            |
| `{ bindir }`   | binaries of the installed distribution   |
| `{ port }`     | the instance's TCP port                  |
| `{ name }`     | the instance name                        |

Substitution is **pure variable replacement — templates never run through a shell**. There is
no string-concatenation-into-bash surface, which means no shell-injection surface.

## The family mechanism

The `family` field groups engines that share a common lineage. A MariaDB manifest declares
`family: mysql`, so it inherits the client-tooling behavior of the MySQL world:

- `dbpod exec <instance>` opens the right SQL shell (`mysql` for the whole MySQL family),
- admin-tool stop strategies apply family-wide,
- toolboxes work the same way (`mysqldump` comes from the same distribution).

Families let one well-understood lifecycle describe many engines, while per-engine manifests
still customize everything that differs.

## Version indexes: generated offline

Manifests don't hardcode version lists. Each source ships a **version index** (JSON) that
maps series → known versions → download metadata:

- Indexes are **generated offline** by the `gen.py` script in the engine source repo (e.g.
  dbpod-ext), typically by crawling upstream releases at authoring time.
- dbpod never crawls the web at runtime — it only reads the index, which keeps installs fast
  and deterministic.
- `dbpod registry update` refreshes indexes when the source publishes a new one.

This split — generation offline, consumption offline-able — is what lets dbpod stay a static
binary with no background network machinery.

## The safety model

Engine manifests are third-party input, so execution is constrained by design:

1. **No shell in templates.** Lifecycle commands are pure variable substitution — nothing is
   ever parsed by a shell.
2. **Binaries resolve inside the distribution only.** Lifecycle entries like `start` are
   forced to resolve to binaries within the installed engine directory — a manifest cannot
   reach for arbitrary system executables.
3. **Writes are locked to the instance datadir.** Server data, logs, tmp, socket, and pid
   files stay inside `./.dbpod/<name>/`. A misbehaving engine can't scatter state across the
   machine.

## Checklist for a new engine

1. Copy the closest manifest from dbpod-ext (by family, or by archive layout).
2. Point `download.url` at the upstream release archives (templated per
   version/platform/arch).
3. Fill in lifecycle commands using the template variables.
4. Set `family` so client-tooling behavior matches the lineage.
5. Generate the version index with `gen.py`, then:

```bash
dbpod registry add ./your-engine.yaml
dbpod engine install your-engine@series
dbpod run --name test --engine your-engine@series
```

That's the entire integration. If it works for you, open a PR to dbpod-ext so it works for
everyone.
