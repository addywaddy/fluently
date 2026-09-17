# Deploying the pilot

One Phoenix release plus PostgreSQL. Deploy a single app instance behind an HTTPS reverse proxy.
A hosting destination is not configured in this repository.

## Build

```sh
docker build -t fluently .
```

The generated multi-stage Dockerfile pins the Elixir/OTP and Debian versions, builds the standalone
embed and runs as an unprivileged user. There is no Node runtime dependency. The local Docker daemon
must be running to validate/build the image. Alternatively, build a release on the same OS/architecture
as the deployment target:

```sh
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
```

## Runtime configuration

Supply through your host’s secret store or an uncommitted env file:

- `DATABASE_URL`: PostgreSQL connection URL. Create the database before migrations.
- `DATABASE_SSL=true`: verify TLS certificates using the system CA store; use a trusted provider certificate.
- `SECRET_KEY_BASE`: generate with `mix phx.gen.secret`; keep stable across deploys and confidential.
- `PHX_HOST`: public service hostname, without scheme or path.
- `PORT`: default 4000.
- `POOL_SIZE`: default 10.

`bin/server` sets `PHX_SERVER=true`. Production enforces HTTPS and secure session cookies.
The reverse proxy must overwrite `X-Forwarded-Proto`; expose the app port only to that proxy.
Project origin allowlists refer to the customer website, not the service hostname.

Run once per deployment before starting/replacing the app:

```sh
docker run --rm --env-file .env fluently /app/bin/migrate
```

Provision each pilot owner once (choose a workspace name):

```sh
docker run --rm --env-file .env fluently /app/bin/fluently eval 'Fluently.Release.create_workspace("Studio")'
```

Save the printed owner key securely and deliver it privately to that owner. Do not publish logs
containing it. The owner signs in at `/app/login` and creates their own projects.

Run the service behind the proxy, for example:

```sh
docker run --init --restart unless-stopped --env-file .env -p 127.0.0.1:4000:4000 fluently
```

Use managed PostgreSQL backups with a documented retention/deletion policy. Test restoration.
Request-body limits are 32 KiB. Tokens and comment parameters are filtered from Phoenix request logs;
do not enable body/header logging at the proxy. Invites are fragments and are removed by the embed,
but host-page scripts can still see them before removal. Deploy the embed only on trusted sites.

The limiter is per-process, expires buckets after 60 seconds, and fails closed at its 20,000-bucket cap.
Invite exchange: 20/IP/min and 60/project/min. Authenticated API: 180 reads and 40 writes/token/min.
Owner login: 10/IP/min. Behind a proxy, IP buckets currently use the proxy’s transport IP; this is
conservative for a small pilot. Configure trusted-proxy IP handling and shared limits before scaling.

Validate HTTPS sign-in, project creation, and an embed on a different origin after deployment.
Check a comment persists after reload, reply/resolve works, and key rotation denies the old session.
Keep the service URL stable because installed snippets reference it.
