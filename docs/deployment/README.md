# Wishlist database and application services

For complete fresh-host setup, routine deployments, smoke checks and diagnosis,
use the [operations runbook](runbook.md). The [manual recovery guide](recovery.md)
documents backing up and restoring existing data. Neither guide was exercised
against the live family installation as part of this documentation update.

These are examples for the parent `dynamic_sites` deployment repository. Merge
the service and volume definitions from `compose.wishlist.yml` into its existing
`docker-compose.yml`; do not replace the parent's other services or volumes.
Paths in the example assume that parent file is the entry point. The
[Nginx/HTTPS guide](nginx/README.md) covers the next stage with only Wishlist's
upstream on the new host.

## Configuration

Create `config/wishlist` in the parent repository. Copy `db.env.example` there as
`db.env` and `app.env.example` as `app.env`. Confirm the real files are ignored by
Git, restrict their permissions to your user, and save their values in 1Password.
The parent's existing `.env` ignore rule does not cover `app.env` or `db.env`.
Add these explicit entries to its `.gitignore` before creating the real files:

```gitignore
/config/wishlist/app.env
/config/wishlist/db.env
```

These files are read by your local Compose client, not from the droplet's disk.

Replace the placeholders before starting anything. Generate a database password
with `openssl rand -hex 32` and use the same value in both files. Generate a
separate `SECRET_KEY_BASE` with `openssl rand -hex 64`; preserve it across
deployments so sessions and signed tokens remain valid.

Set `WISHLIST_HOST=mywishlist.top`, `DEVISE_MAILER_SENDER=Wishlist
<wishlist@mywishlist.top>`, and `SMTP_PASSWORD` to your Resend API key. The SMTP
defaults are `smtp.resend.com`, port `2587`, username `resend`, with required
STARTTLS and normal certificate verification. Other SMTP providers can be used
by changing the address, port and username, provided they support STARTTLS.
Web and worker both receive these settings; application code still sends email
only through jobs. Delivery errors fail the job rather than being swallowed.

`REGISTRATION_NOTIFICATION_EMAIL` optionally identifies an existing user's
account email for new-account alerts. Set it to your own account's email when
bootstrapping your user, or leave it blank to disable alerts. It is independent
of the sender address. Production mail URLs use HTTPS and the configured host.
Other hosts are rejected, except for `/up` so internal health checks can work.

The test variables are temporary unused boot placeholders, not production
database values. Wait to enable public access and send invitations until after
Nginx/TLS and a real worker email have been verified.

## Why these settings

- Web and worker use the image already built on the new droplet. Only web has a
  build definition, so `docker compose build wishlistweb` refreshes their shared
  `wishlist:production` tag. `bin/jobs` consumes all queues using the existing
  configuration.
- PostgreSQL has a separate volume and no published port. PostgreSQL 18 stores
  its versioned data under `/var/lib/postgresql`; this is the volume mount point,
  unlike the `/var/lib/postgresql/data` used by the old sites.
- The PostgreSQL image creates the `wishlist` login and initial database on first
  initialization. This login is its bootstrap superuser, confined to Wishlist's
  dedicated database instance. Rails creates the queue, cache and cable databases
  with `db:prepare`.
- Database health uses TCP, so the temporary socket-only initialization server
  does not make it ready prematurely. `$$` passes environment variable expansion
  to the container shell rather than Compose's interpolation.
- `service_healthy` makes Compose wait for database readiness at startup. It does
  not supervise dependencies after a daemon restart or recreate an unhealthy
  container automatically.
- Web and worker share a persistent Active Storage volume. It is separate from
  the database volume. Both are persistence, not backups.
- No host port is published for Rails. Nginx will proxy to `wishlistweb:3000` over
  the Compose network. The web health check verifies Rails `/up`, not database
  availability or queue processing.
- Restart policies and bounded JSON logs are set on all three services.

## Start and verify only PostgreSQL

Run from the parent repository with your shell targeting the new droplet:

```sh
eval "$(rancher-machine env dynamicsites-next)"
docker info --format 'Name={{.Name}} Version={{.ServerVersion}}'
docker compose config --quiet
docker compose up -d --wait wishlistdb
docker compose ps wishlistdb
docker compose exec wishlistdb sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT version();"'
```

`config --quiet` validates without printing resolved secrets. Explicitly naming
`wishlistdb` starts no old application services. Compose may still warn about
unset interpolation variables in their definitions; it parses the whole file.
Required env files for other services must also exist when using the parent file.
If validation fails, fix that before starting services; do not substitute a bare
`docker compose up`.

PostgreSQL initialization settings only apply to an empty volume. Editing the
password in `db.env` later does not change the existing PostgreSQL role password.
Use normal database administration to rotate it; retain the existing data volume.

## Prepare databases and start web/worker

After updating the Wishlist submodule checkout and the real `app.env` with the
settings above, run from the parent repository targeting `dynamicsites-next`:

```sh
docker compose config --quiet
docker compose build wishlistweb
docker compose run --rm wishlistweb ./bin/rails db:prepare
docker compose up -d --wait wishlistweb wishlistworker
docker compose ps wishlistdb wishlistweb wishlistworker
docker compose exec -T wishlistweb ./bin/rails db:version
docker compose exec -T wishlistweb curl --fail --silent --show-error http://127.0.0.1:3000/up
docker compose exec -T wishlistweb curl --fail --silent --show-error -o /dev/null -w '%{http_code}\n' -H 'Host: mywishlist.top' http://127.0.0.1:3000/login
docker compose exec -T wishlistworker ./bin/rails runner 'puts SolidQueue::Process.where(kind: "Worker").pluck(:name)'
```

`db:prepare` loads the schema for the existing empty primary database and creates
the cache, queue and cable databases as needed. It is safe to run again and
applies pending migrations. The seed file currently contains no executable code.
Do not use schema loads or seeds copied from the old applications. Run preparation
once before starting web/worker rather than from competing container entrypoints.

Expect Rails schema versions for all four databases, HTTP 200 for `/up` and
`/login`, and at least one registered worker name. `--wait` verifies the web
health check, but the worker has no health check; its running status alone does
not establish job processing. Inspect recent worker output with
`docker compose logs --tail=100 wishlistworker` if no worker registers.

These commands publish no web port and start no legacy application or proxy.
Next configure Nginx/TLS, create the first confirmed user using the README's
console procedure, and verify actual email delivery through a live job. Worker
registration and configured SMTP credentials do not establish actual delivery.

The user has confirmed these remote checks passed on `dynamicsites-next`:
primary `wishlist_production` schema version 20261022143156, cache/queue/cable
schema version 1, healthy PostgreSQL/web, login HTTP 200, and a registered worker.
The worker's running status has no health check; Compose's startup summary saying
Healthy is not an additional worker-processing test.
