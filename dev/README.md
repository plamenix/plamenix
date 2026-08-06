# Local Firebird containers

Two engines, running at the same time, because Plamenix claims support
for **Firebird 2.5 through 5.0** and several code paths are version-gated.
Checking that claim means pointing the same build at both ends of the
range, not just the newest one.

| Engine | Host port | Directory | Image |
|---|---|---|---|
| 5.0 | `127.0.0.1:3050` | `firebird5/` | `firebirdsql/firebird:5` |
| 2.5 | `127.0.0.1:3051` | `firebird25/` | `jacobalberty/firebird:2.5-ss` |

Credentials are the same for both: `SYSDBA` / `masterkey`, database
`test.fdb`.

## Running them

```sh
cd firebird5  && docker compose up -d
cd firebird25 && docker compose up -d && ./seed.sh
```

Firebird 5 seeds itself through the image's
`/docker-entrypoint-initdb.d` hook. The 2.5 image has no such hook — it
creates the database and stops — so `seed.sh` applies the schema
afterwards. It reads `firebird5/init/01-schema.sql` rather than keeping
its own copy: if the two engines ever ran different schemas, every
version comparison made against them would be meaningless.

The 2.5 image publishes `linux/amd64` only, so it runs under emulation
on Apple Silicon. First start is slow — a minute or more — which is why
its healthcheck allows a longer `start_period`. That is not a hang.

Database files live in each directory's `data/` and are gitignored;
delete the directory to start from a clean database.

## Why 2.5 is worth the trouble

It reproduces failures the 5.0 container cannot. For example, the
monitoring columns behind the dashboard do not exist in 2.5:

```sql
SELECT MON$OWNER FROM MON$DATABASE;
-- SQL error code = -206, Column unknown, MON$OWNER
```

`MON$CRYPT_STATE` fails the same way. Anything reading those needs a
version gate, and the gate can only be verified here.

## Running the live tests

Integration tests that need a server are `#[ignore]` by default:

```sh
cd ../../plamenix-core && cargo test -p plamenix-db -- --ignored
```
