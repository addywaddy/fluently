# Deploying the pilot

One Phoenix instance with SQLite on persistent local storage. A hosting destination is
not configured. Litestream is configured as a Kamal accessory; remote backup and restore
verification requires a deployed host and bucket credentials.

## Kamal (recommended)

The repository includes `config/deploy.yml` for **Kamal 2.12+** and the existing Phoenix
Docker release. Install Kamal on your workstation (`gem install kamal -v 2.12.0`);
Ruby is only a deployment tool dependency. Docker must be running locally to build.

The [Terraform configuration](../terraform/README.md) can provision the Hetzner VPS
and private backup bucket; its plan must be reviewed before a separately authorized apply.

Prepare one Linux server with SSH access, ports 80/443 available, and your domain's DNS
pointing to it. Default architecture is amd64; set `FLUENTLY_ARCH=arm64` for an ARM server.
Create a private image repository (default registry: GHCR) and registry credentials.
Export these non-secret settings in your shell (or source an ignored deployment env file):

```sh
export FLUENTLY_SERVER=your-server-ip
export PHX_HOST=feedback.your-domain.com
export FLUENTLY_IMAGE=your-registry-user/fluently
export KAMAL_REGISTRY_USERNAME=your-registry-user
export LITESTREAM_BUCKET=your-dedicated-fluently-backup-bucket
export MAIL_FROM=hello@your-verified-sending-domain.com
# Optional: KAMAL_REGISTRY_SERVER, FLUENTLY_ARCH, FLUENTLY_SSH_USER (default root)
cp .kamal/secrets.example .kamal/secrets
```

Provide `KAMAL_REGISTRY_PASSWORD` and `SECRET_KEY_BASE` through your shell/password manager,
or edit the ignored `.kamal/secrets`. Generate the latter once with `mix phx.gen.secret`
and retain it across deployments. Never commit either credential. Deployment settings
used by ERB belong in the shell environment, not only in `.kamal/secrets`.

```sh
kamal server bootstrap      # install Docker on the target host
# Initialize ownership BEFORE accessories boot (only needed for a new volume).
ssh "${FLUENTLY_SSH_USER:-root}@$FLUENTLY_SERVER" \
  'docker run --rm -v fluently_data:/data alpine:3.21 sh -c "chown 65534:65534 /data && chmod 700 /data"'
kamal setup                 # first deployment: starts accessories and app
kamal deploy                # subsequent deployments
kamal app logs
```

Kamal builds from committed files: commit changes before deploying. `kamal config`
validates the configuration locally, but can display secrets; do not share its output.
No server has been contacted or provisioned by this repository setup.

Kamal mounts **`fluently_data:/data`**, runs migrations before Phoenix starts, and checks
`/up` before switching traffic. The volume preparation above sets writable `/data` permissions for both containers. Keep this volume across deployments; do not delete it or scale this config
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
See the backup setup and restore procedure below.

References: [Kamal configuration](https://kamal-deploy.org/docs/configuration/overview/),
[proxy and health checks](https://kamal-deploy.org/docs/configuration/proxy/),
[Phoenix releases](https://phoenix.hexdocs.pm/Mix.Tasks.Phx.Gen.Release.html).

## Transactional email (Resend)

Verify a sending domain in Resend using the DNS records it provides. Create a sending API
key restricted to that domain where possible, then provide `RESEND_API_KEY` through your
shell/password manager or ignored `.kamal/secrets`. Export `MAIL_FROM` as a bare email
address on the verified domain, for example `hello@mail.your-domain.com`. Kamal passes
the API key as a secret and the sender as a clear runtime setting.

Production requires both variables at startup and uses `Swoosh.Adapters.Resend` through
`Fluently.Mailer`. `Fluently.Mailer.sender/0` returns the configured sender tuple for future
email templates. Development still previews emails at `/dev/mailbox`, and tests use
Swoosh's test adapter without sending external email.

This configures the delivery provider only. Verification, password resets, invitations,
and comment notifications do not send email yet. No live test email was sent during
setup. Once those flows are implemented, verify delivery to an address you control.

Reference: [Resend Swoosh adapter](https://swoosh.hexdocs.pm/Swoosh.Adapters.Resend.html).

## Litestream backups

Create a **dedicated private bucket in Hetzner's nbg1 region**, then export its name as
`LITESTREAM_BUCKET`. Provide `LITESTREAM_ACCESS_KEY_ID` and
`LITESTREAM_SECRET_ACCESS_KEY` in your shell/password manager or ignored `.kamal/secrets`.
Use credentials authorized to list/read/write/delete backup objects in that bucket.
Do not reuse Chronologs' bucket/path combination. No credentials were copied from it.

`config/litestream.yml` replicates `/data/fluently.db` to `production` in that bucket.
It uses the nbg1 endpoint, path-style S3 requests, daily snapshots and seven-day retention.
Adjust provider/region there if needed. Deleted application data may remain in retained
backups. Bucket lifecycle rules must not remove objects still needed by Litestream.

For an existing Kamal installation, prepare/check volume ownership as above, then run:

```sh
kamal accessory boot litestream
kamal accessory logs litestream
```

Normal `kamal deploy` leaves the accessory running. After changing its config, credentials
or pinned image, run `kamal accessory reboot litestream`. Run only one replicator for this
database. Backups are asynchronous, so unsynced writes can be lost if the host fails.
Monitor accessory logs for upload failures and verify fresh objects in the bucket.
Do not treat a healthy application endpoint as evidence that backups are working.

### Restore drill / recovery

On the deployment server, set `LITESTREAM_BUCKET`, `LITESTREAM_ACCESS_KEY_ID`, and
`LITESTREAM_SECRET_ACCESS_KEY` securely in the shell. Place the repository's
`config/litestream.yml` at an absolute local path, represented by `$LITESTREAM_CONFIG`:

```sh
export LITESTREAM_CONFIG=/absolute/path/to/litestream.yml
docker volume create fluently_restore
docker run --rm -v fluently_restore:/data alpine:3.21 \
  sh -c 'chown 65534:65534 /data && chmod 700 /data'
docker run --rm --user 65534:65534 \
  -e LITESTREAM_BUCKET -e LITESTREAM_ACCESS_KEY_ID -e LITESTREAM_SECRET_ACCESS_KEY \
  -v fluently_restore:/data -v "$LITESTREAM_CONFIG:/etc/litestream.yml:ro" \
  litestream/litestream:0.5.14 restore -config /etc/litestream.yml /data/fluently.db
```

Use a fresh volume for each drill. Missing backups or an existing destination must fail;
do not add flags that silently skip restoration. This command only reads remote backups.
Check `PRAGMA integrity_check` and `PRAGMA foreign_key_check` with SQLite, then verify
representative accounts, threads, replies and anchors in an isolated application instance.
Do not start a second replicator against the production prefix during a drill.

For actual recovery, stop the app **and** accessory first (`kamal app stop` and
`kamal accessory stop litestream`). Restore into the new volume, verify it, then change
**both** volume mappings in `config/deploy.yml` to the restored volume. Retain the old
volume for investigation. Deploy the application and reboot the accessory using the new
mapping. Never copy a restored file over an active database or retain stale WAL/SHM files.

References: [Litestream configuration](https://litestream.io/reference/config/),
[restore](https://litestream.io/reference/restore/).

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
- `RESEND_API_KEY`: sending API key (secret).
- `MAIL_FROM`: sender email address on a verified Resend domain.
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
