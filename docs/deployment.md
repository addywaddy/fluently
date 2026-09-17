# Deploying the pilot

One Phoenix instance with SQLite on persistent local storage. A hosting destination is
not configured. Litestream is the intended backup approach but is deferred; automated
remote backups and restore are not configured yet.

## Kamal (recommended)

The repository includes `config/deploy.yml` for **Kamal 2.12+** and the existing Phoenix
Docker release. Install Kamal on your workstation (`gem install kamal -v 2.12.0`);
Ruby is only a deployment tool dependency. Docker must be running locally to build.

Prepare one Linux server with SSH access, ports 80/443 available, and your domain's DNS
pointing to it. Default architecture is amd64; set `FLUENTLY_ARCH=arm64` for an ARM server.
Create a private image repository (default registry: GHCR) and registry credentials.
Export these non-secret settings in your shell (or source an ignored deployment env file):

```sh
export FLUENTLY_SERVER=your-server-ip
export PHX_HOST=feedback.your-domain.com
export FLUENTLY_IMAGE=your-registry-user/fluently
export KAMAL_REGISTRY_USERNAME=your-registry-user
# Optional: KAMAL_REGISTRY_SERVER, FLUENTLY_ARCH, FLUENTLY_SSH_USER (default root)
cp .kamal/secrets.example .kamal/secrets
```

Provide `KAMAL_REGISTRY_PASSWORD` and `SECRET_KEY_BASE` through your shell/password manager,
or edit the ignored `.kamal/secrets`. Generate the latter once with `mix phx.gen.secret`
and retain it across deployments. Never commit either credential. Deployment settings
used by ERB belong in the shell environment, not only in `.kamal/secrets`.

```sh
kamal setup                 # first deployment: prepares host, builds and starts app
kamal deploy                # subsequent deployments
kamal app logs
```

Kamal builds from committed files: commit changes before deploying. `kamal config`
validates the configuration locally, but can display secrets; do not share its output.
No server has been contacted or provisioned by this repository setup.

Kamal mounts **`fluently_data:/data`**, runs migrations before Phoenix starts, and checks
`/up` before switching traffic. The fresh volume inherits the image's writable `/data`
permissions. Keep this volume across deployments; do not delete it or scale this config
to multiple servers. The HTTP health route is excluded from SSL redirection; all normal
routes retain HTTPS enforcement. Kamal terminates TLS and forwards the scheme; do not
publish port 4000 directly to the internet.

Normal rolling deployments briefly run old/new versions on the same database. Use only
backward-compatible migrations. For an incompatible migration, stop the app first with
`kamal app stop`, then deploy during a maintenance window. A failed migration prevents
that container from becoming healthy. `kamal rollback VERSION` rolls back the application
image only; it does not undo migrations or restore deleted data.

After initial deployment, sign up and create projects through `/app`. To enable the
landing demo, create a project for the production HTTPS origin, export its public UUID
as `FLUENTLY_PROJECT_ID`, and deploy again. Local demo data is not uploaded automatically.
Litestream remains deferred.

References: [Kamal configuration](https://kamal-deploy.org/docs/configuration/overview/),
[proxy and health checks](https://kamal-deploy.org/docs/configuration/proxy/),
[Phoenix releases](https://phoenix.hexdocs.pm/Mix.Tasks.Phx.Gen.Release.html).

## Manual Docker deployment

The following is an alternative to Kamal, not an additional setup step. It uses a
different example volume name; never mix the two workflows for the same installation.

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
