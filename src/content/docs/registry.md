---
title: Registry
description: Manage where engines come from — list, add, update, enable, and disable engine sources.
order: 6
---

## What the registry is

The registry is dbpod's list of **engine sources**. Each entry describes where engine
definitions (manifests + version indexes) come from. Out of the box, dbpod ships with the
builtin registry; community sources such as `dbpod-ext` can be added alongside it.

## Commands

```bash
dbpod registry ls               # list configured sources
dbpod registry add ./my.yaml    # register a local or remote source
dbpod registry update           # refresh version indexes and builtin metadata
dbpod registry enable <name>    # re-enable a disabled source
dbpod registry disable <name>   # hide a source without deleting it
dbpod registry rm <name>        # remove a configured source
```

## Builtin semantics

The builtin source is special:

| Action            | Builtin source                  | Configured source |
| ----------------- | ------------------------------- | ----------------- |
| update metadata   | ✓ (`registry update`)           | ✓                 |
| disable (= hide)  | ✓ — hidden from listings        | ✓                 |
| remove            | ✗ — cannot be deleted           | ✓                 |

Disabling the builtin source doesn't destroy it — installed engines keep working — it only
hides builtin definitions from new installs. This gives teams a way to enforce "our engines
only" without hacking the installation.

## index_url: three forms

A registry entry points at its version index through `index_url`, which accepts three forms:

1. **Relative path** — resolved against the manifest's own location. Ideal for sources
   checked into a repository next to their manifests.
2. **Absolute path** — a fixed location on the local machine. Useful for internal,
   ops-managed engine catalogs.
3. **Protocol URL** — `https://…` (and other supported schemes) for remotely hosted indexes.
   Teams can serve their own engine index without publishing anything to the builtin source.

```yaml
# an example registry entry
name: my-engines
manifest: ./engines/mariadb.yaml
index_url: indexes/mariadb.json   # relative to the manifest
```

## Updating

`dbpod registry update` re-reads every enabled source and refreshes:

- builtin engine metadata (so series like `mysql@8.0` resolve to newly released patches), and
- version indexes of configured sources.

The update pulls from the sources' declared locations; it never requires engines to be
reinstalled — cached binaries under `DBPOD_HOME/versions` stay valid.
