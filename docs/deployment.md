# Deploying the pilot

One Phoenix instance with SQLite on persistent local storage. A hosting destination is
not configured. Litestream is the intended backup approach but is deferred; automated
remote backups and restore are not configured yet.

## Build and configuration

```sh
docker build -t fluently .
docker volume create fluently-data
```

The image runs as `nobody` and defaults to `DATABASE_PATH=/data/fluently.db`.
A fresh named volume inherits `/data` permissions. For an existing volume, ensure UID
65534 can write to its directory and files. Keep the entire directory persistent:
SQLite also uses WAL and shared-memory files. Do not use network filesystems or run
multiple application replicas against this file. Never bake databases into the image.

Supply through your host's secret store or an ignored `.env` file:

- `SECRET_KEY_BASE`: generate with `mix phx.gen.secret`; keep stable across deployments.
- `PHX_HOST`: public hostname without scheme/path.
- Optional `DATABASE_PATH`: absolute path on persistent local storage (required for native releases).
- `PORT`: default 4000.
- `POOL_SIZE`: default 5.
- `FLUENTLY_PROJECT_ID`: optional public project UUID for the landing demo.

## Initialize and run

Run migrations before starting the application, mounting the same persistent volume:

```sh
docker run --rm --env-file .env -v fluently-data:/data fluently /app/bin/migrate
```

Run behind an HTTPS reverse proxy:

```sh
docker run -d --name fluently --init --restart unless-stopped \
  --env-file .env -v fluently-data:/data -p 127.0.0.1:4000:4000 fluently
```

Stop the old application before migrating and starting its replacement. Reuse the same
volume; a new empty volume creates an empty database. Production enforces HTTPS and
secure cookies. The proxy must overwrite `X-Forwarded-Proto`; expose the application port
only to that proxy. Register at `/signup` and create projects in `/app`.

Optional pilot owner provisioning:

```sh
docker exec fluently /app/bin/fluently eval 'Fluently.Release.create_workspace("Studio")'
```

Save the printed owner key privately. Do not publish logs containing credentials.

## Native releases

Build on the same OS/architecture as deployment:

```sh
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
```

Set the runtime variables above and create a writable directory for `DATABASE_PATH`.
Run `bin/migrate`, then `bin/server`. Local development uses `data/fluently_dev.db` and
needs no separate database service. Database tests use their own SQLite file.

## PostgreSQL cutover

The pre-production local dataset was transferred with IDs, timestamps, credential hashes
and anchor/context maps intact and every record compared after import. The source
PostgreSQL database is unchanged. An ignored, mode-0600 export is in
`tmp/postgres-export.etf`; treat it as sensitive and remove it once rollback is no longer
needed. Never commit it. The initial migrations now target SQLite, not PostgreSQL.
Do not switch back after accepting new writes without migrating those new records too.

## Pilot checks

Set up and test backups before production launch. Copying only an active `.db` file can
omit committed data still in its WAL; use SQLite's backup facilities for a consistent copy.

Request bodies are limited to 32 KiB. Avoid body/header logging at the proxy.
The in-memory limiter remains single-instance. Behind a proxy, IP limits currently use
the proxy transport IP; configure trusted-proxy handling before scaling.
Validate HTTPS sign-in, project creation, another-origin embed, comment persistence,
reply/resolve/delete, and credential rotation. Keep the public service URL stable.
