---
title: Instances
description: Create and manage instances — detached run, graceful stop, --rm cleanup, ports, and the per-instance monitor.
order: 3
---

## Concept

An **instance** is a running database server created from an engine — the analogue of a Docker
container. It is identified by name within the project and keeps all of its state in
`./.dbpod/<name>/`.

## Lifecycle

```bash
dbpod run --name dev --engine mysql@8.0     # create + start (detached)
dbpod ps                                    # list instances
dbpod stop dev                              # graceful stop
dbpod restart dev                           # stop + start
dbpod start dev                             # start a stopped instance
dbpod rm dev                                # remove instance + datadir
```

`run` returns only after the server is ready to accept connections — no log-watching, no
"wait a few seconds". Like Docker, the process is detached: your shell is free the moment the
command exits.

### Stop now means stop later — in three levels

`stop` shuts an instance down through a graceful escalation chain:

1. **Admin tool** — ask the server to shut down via its own admin command.
2. **SIGTERM** — if the admin tool is unavailable or too slow.
3. **SIGKILL** — last resort.

Your data safety is handled by the engine's own durability guarantees, not by dbpod's
optimism.

### --rm: containers semantics

```bash
dbpod run --rm --name ci --engine postgres@17
```

With `--rm`, stopping the instance also removes it and its datadir — ideal for CI jobs and
scratch environments.

## Data directory

Everything the server writes is locked inside the project:

```text
./.dbpod/
└── dev/
    ├── data/      # the actual database files
    ├── logs/
    ├── tmp/
    ├── socket/
    └── pid
```

No writes to system paths, ever. Commit nothing, keep everything portable: move the project,
move the database.

## Ports and binding

`run` prints the bound address (e.g. `127.0.0.1:3306`). You can control exposure explicitly:

```bash
dbpod run --name dev --engine mysql@8.0 --port 13306
```

Instances are reachable over TCP on every platform — on Windows, where unix sockets don't
exist, TCP is simply the native path.

## Supervision

Each instance is watched by a lightweight per-instance monitor (conmon-style):

- The monitor survives your terminal — closing the shell does not stop the database.
- If the monitor loses track of the server PID, it recovers it from the instance's pidfile
  instead of guessing.
- Monitors perform the graceful-stop escalation and apply `--rm` cleanup when the instance
  stops.

## Logs

```bash
dbpod logs dev            # current log output
dbpod logs dev --follow   # stream
```

Logs live inside the datadir, so they travel with the project like everything else.
