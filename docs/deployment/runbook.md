# Wishlist deployment and operations

This guide describes the working Wishlist deployment on `dynamicsites-next`.
Run commands from a **local Bash shell**, in the root of `dynamic_sites`, unless
explicitly told to use a Rails console. Rancher Machine selects the remote Docker
daemon; Compose reads source code and environment files from your local checkout.
You do not need to clone the repositories onto the droplet.

Run each stage separately and stop if a command fails. Fresh installation creates
empty databases. Recovering existing accounts/lists requires the separate
`sites/wishlist/docs/deployment/recovery.md` procedure and actual backups.

## Deployment layout

| Component | Configuration |
| --- | --- |
| Host | Rancher Machine `dynamicsites-next`, Ubuntu 24.04 LTS; initially Docker 29.9.2 |
| Domain | `mywishlist.top` |
| Application source | Git submodule `sites/wishlist` |
| Compose entry point | `dynamic_sites/docker-compose.yml`; project name `dynamic_sites` |
| Web and worker image | `wishlist:production` |
| Database | `postgres:18.6-alpine3.24`, service `wishlistdb` |
| Rails databases | `wishlist_production`, `_cache`, `_queue`, `_cable` |
| App settings | Local, untracked `config/wishlist/app.env` |
| PostgreSQL settings | Local, untracked `config/wishlist/db.env` |
| Proxy build | `config/nginx/Dockerfile` copies only `config/nginx/mywishlist.conf` |
| Persistent volumes | `wishlistdb-data`, `wishlist-storage`, `nginx_secrets` |

The current proxy base is `jonasal/nginx-certbot:6.2.0-nginx1.31.8-alpine`.
Web listens internally on 3000 and PostgreSQL on 5432. Only Nginx publishes host
ports 80 and 443. Seeing `3000/tcp` on the worker reflects the shared image's
EXPOSE declaration; it does not mean the worker runs a web server.

Explicitly name services in deployment commands. The parent Compose file also
contains old applications; bare `docker compose up`, `down`, or indiscriminate
rebuilds would have a broader effect. Keep the Compose project name stable so
the same named volumes are reused.

## 1. Local tools and repository

Have Git with GitHub SSH access, Rancher Machine, Docker CLI with Compose and
Buildx, curl, OpenSSL, and dig installed locally. Check:

```bash
git --version
rancher-machine --version
docker --version
docker compose version
docker buildx version
curl --version
openssl version
dig -v
```

For a new checkout:

```bash
git clone --recurse-submodules git@github.com:seaneshbaugh/dynamic_sites.git
cd dynamic_sites
git submodule sync --recursive
git submodule update --init --recursive
```

For an existing checkout, first review/commit your intended local changes, then:

```bash
git status --short
git pull --ff-only
git submodule sync --recursive
git submodule update --init --recursive
git submodule status sites/wishlist
```

This checks out the Wishlist commit recorded by the parent repository. It does
not automatically advance Wishlist to the newest upstream commit. To intentionally
deploy a newer Wishlist revision, update the submodule to that reviewed commit
and commit the changed submodule pointer in `dynamic_sites` before deployment.

## 2. Create a fresh droplet, when needed

Skip this section for the running host. Creation is a real, billable operation.
Use a new, unused machine name if replacing a host that is still registered.

Create a DigitalOcean custom-scope API token with `droplet:create`,
`droplet:read`, `ssh_key:create`, and `ssh_key:read`, plus the dependencies the UI
requires (`regions:read`, `sizes:read`, `actions:read`, `image:read`,
`snapshot:read`, `vpc:read`). Add `droplet:update` for power/reboot operations and
`droplet:delete`/`ssh_key:delete` if Machine will remove resources later.

Read the token without recording its literal value in shell history:

```bash
read -r -s -p 'DigitalOcean API token: ' DIGITALOCEAN_ACCESS_TOKEN
printf '\n'
export DIGITALOCEAN_ACCESS_TOKEN
WISHLIST_MACHINE=dynamicsites-next

rancher-machine create \
  --driver digitalocean \
  --digitalocean-region nyc2 \
  --digitalocean-size s-2vcpu-4gb \
  --digitalocean-image ubuntu-24-04-x64 \
  "$WISHLIST_MACHINE"

unset DIGITALOCEAN_ACCESS_TOKEN
```

The driver reads `DIGITALOCEAN_ACCESS_TOKEN` from the environment. The size slug
selects Basic Regular, 2 vCPUs / 4 GiB RAM / 80 GiB SSD; verify current price and
regional availability before creation. This path successfully provisioned the
current host. If provisioning fails, inspect DigitalOcean and `rancher-machine
ls` before retrying: a partially provisioned droplet can still exist and be billed.

Save the machine's local registration/SSH keys and provider credentials securely.
`~/.docker/machine` contains private material and shared certificates; it belongs
in encrypted storage rather than Git. A different computer needs that registration
and corrected local paths to manage this same machine.

## 3. Select and verify the remote host in every new shell

```bash
WISHLIST_MACHINE=dynamicsites-next
unset DOCKER_CONTEXT DOCKER_API_VERSION DOCKER_BUILDKIT
eval "$(rancher-machine env "$WISHLIST_MACHINE")"
export COMPOSE_PROJECT_NAME=dynamic_sites

rancher-machine ip "$WISHLIST_MACHINE"
printf 'Docker endpoint: %s\n' "$DOCKER_HOST"
docker info --format 'Name={{.Name}} Version={{.ServerVersion}} OS={{.OperatingSystem}}'
docker version
```

Confirm the endpoint contains the new droplet's IP and Docker reports the
intended host, not local Docker Desktop or the old `dynamicsites`. Docker's Name
comes from the Linux hostname, which can differ from the Machine alias after
renaming. `DOCKER_CONTEXT` can override the selected endpoint; a stale forced
API version or `DOCKER_BUILDKIT=0` is unnecessary on this modern host.

For direct inspection or an interactive SSH shell:

```bash
rancher-machine ssh "$WISHLIST_MACHINE" 'cat /etc/os-release'
rancher-machine ssh "$WISHLIST_MACHINE" 'uname -r'
rancher-machine ssh "$WISHLIST_MACHINE"
```

Exit SSH before resuming the local Compose commands. To leave the remote Docker
environment in your local shell:

```bash
eval "$(rancher-machine env --unset)"
```

## 4. Restore runtime settings from 1Password

On a new local checkout, create the settings files from the existing production
values in 1Password. For a completely new installation, copy the examples first:

```bash
mkdir -p config/wishlist
cp sites/wishlist/docs/deployment/db.env.example config/wishlist/db.env
cp sites/wishlist/docs/deployment/app.env.example config/wishlist/app.env
chmod 600 config/wishlist/db.env config/wishlist/app.env
```

Do not overwrite existing production settings with these copy commands. Ensure
the parent's `.gitignore` contains `/config/wishlist/app.env` and
`/config/wishlist/db.env`, then verify:

```bash
git check-ignore config/wishlist/app.env config/wishlist/db.env
```

Edit both files locally. Important relationships:

- `POSTGRES_DB` and `WISHLIST_DATABASE` are `wishlist_production`.
- `POSTGRES_USER` and `WISHLIST_DATABASE_USERNAME` name the same database role.
- `POSTGRES_PASSWORD` and `WISHLIST_DATABASE_PASSWORD` must match.
- App host is `wishlistdb`, port 5432; the database name is not the username.
- `SECRET_KEY_BASE` must stay stable across rebuilds/restores to preserve sessions
  and signed invitations. Supply `RAILS_MASTER_KEY` too if encrypted credentials
  are used; the current settings use runtime environment variables.
- `WISHLIST_HOST=mywishlist.top`; sender is `Wishlist <wishlist@mywishlist.top>`.
- `SMTP_PASSWORD` is the Resend API key. Defaults are smtp.resend.com, 2587,
  username resend, required STARTTLS. Keep `SOLID_QUEUE_IN_PUMA` unset.
- `REGISTRATION_NOTIFICATION_EMAIL` optionally names your existing account for
  registration alerts. Blank disables alerts; this is separate from the sender.
- Retain the unused `WISHLIST_TEST_DATABASE*` placeholders from the example:
  the current YAML evaluates those entries during production boot too.

For a new installation only, generate separate values and save them in 1Password:

```bash
openssl rand -hex 32
openssl rand -hex 64
```

Use the first as the database password and the second as `SECRET_KEY_BASE`.
Restore the original signing secret for data recovery rather than generating
a replacement. Changing `POSTGRES_*` in an env file does not change an already
initialized database role or password.

The parent file's other services can reference their own required env files and
interpolation variables even when they are not being started. Restore those
local configuration files if needed to parse the parent Compose file. Currently
these include `config/cavesofkoilos/.env`, `config/seaneshbaugh/.env`,
`config/texashardcore/.env`, and `config/spritesheet/.env`; the parent `.env` may
also supply their build-argument interpolation values. They are not bundled with
Git. This does not require starting those services. Check:

```bash
docker compose config --quiet
```

This validates without printing resolved secrets. Avoid sharing full `docker
compose config`, full container inspections, env files, or environment dumps.

## 5. First installation on empty volumes

If restoring backups, use the recovery guide before database preparation instead
of this empty-install sequence. Ensure Compose's nginx build points at the actual
`config/nginx/Dockerfile`, and that it copies `mywishlist.conf` only.

Build before starting the application:

```bash
docker compose build wishlistweb nginx
docker image inspect wishlist:production --format 'ID={{.Id}} User={{.Config.User}} Size={{.Size}}'
docker compose up -d --wait --wait-timeout 120 wishlistdb
docker compose exec -T wishlistdb sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT version();"'
docker compose run --rm --no-deps --pull never wishlistweb ./bin/rails db:prepare
docker compose up -d --no-build --pull never --wait --wait-timeout 120 wishlistweb wishlistworker
docker compose ps wishlistdb wishlistweb wishlistworker
docker compose exec -T wishlistweb ./bin/rails db:version
```

The application image serves web and worker; only web has a build definition.
Database preparation creates/migrates primary, cache, queue and cable before the
worker starts. The seed file currently contains comments only. Do not copy the
old sites' `db:schema:load` or `db:seed` commands into normal deployment.

PostgreSQL and web should report healthy. The worker has no health check:
`--wait` ensures it is running, and the explicit worker checks below establish
more. A displayed `3000/tcp` or `5432/tcp` without a host mapping is not a public
port. Application ports remain internal to the Compose network.

## 6. DNS, HTTPS and the first account

Get the new IP, then set Namecheap's root (`@`) A record for `mywishlist.top` to it:

```bash
rancher-machine ip "$WISHLIST_MACHINE"
dig +short A mywishlist.top
dig +short AAAA mywishlist.top
```

Replace parking/URL redirect records that conflict with the website. An AAAA
record must reach working IPv6 on this same host; remove it if not using IPv6.
Keep mail MX/TXT/DKIM records. Allow inbound TCP 80/443 through any cloud/host
firewall while retaining SSH and secured Docker API access.

After public DNS resolves to the new host:

```bash
docker compose up -d --no-build --wait --wait-timeout 180 nginx
docker compose logs --tail=100 -f nginx
```

Ctrl-C stops following logs without stopping the container. First startup can
temporarily disable HTTPS until Certbot obtains the certificate. Look for
successful issuance, enabling the config, and a successful Nginx reload.
`STAGING=0` requests a trusted certificate; the image checks renewals every 12h.
`--wait` sees nginx running, not certificate readiness, so use the HTTPS check:

```bash
docker compose exec -T nginx nginx -t
curl --fail --head http://mywishlist.top/login
curl --fail --head https://mywishlist.top/login
curl --fail --silent --show-error https://mywishlist.top/up
```

Expect HTTP redirect, HTTPS 200 and the green health page, with normal TLS
verification. Open `/login` in a browser to confirm styling and JavaScript.

On a new empty installation, bootstrap the first confirmed account:

```bash
docker compose exec wishlistweb ./bin/rails console
```

In that Rails console, substitute your username/email:

```ruby
require "io/console"
user = User.new(username: "your_username", email: "you@example.com")
user.password = IO.console.getpass("Password: "); nil
user.password_confirmation = IO.console.getpass("Confirm password: "); nil
user.skip_confirmation!
user.save!
exit
```

Password input is hidden and the assignments return nil to avoid echoing it.
Normal validations still run. After restoring existing data, use your restored
account instead of creating a duplicate bootstrap user.

## 7. Routine application deployment

Select/verify the target as above. Commit intended local changes and ensure the
parent records the intended Wishlist revision. Build while the old app runs;
stop web/worker only for the migration/startup window. This conservative sequence
permits a short interruption and does not assume every migration is compatible
with old application processes.

First retain the currently running image, before pulling source or rebuilding:

```bash
WISHLIST_DEPLOY_ID=$(date -u +%Y%m%dT%H%M%SZ)
WISHLIST_ROLLBACK_IMAGE="wishlist:rollback-$WISHLIST_DEPLOY_ID"
WISHLIST_OLD_IMAGE_ID=$(docker inspect --format '{{.Image}}' "$(docker compose ps -q wishlistweb)")
docker image tag "$WISHLIST_OLD_IMAGE_ID" "$WISHLIST_ROLLBACK_IMAGE"
printf 'Rollback image: %s\n' "$WISHLIST_ROLLBACK_IMAGE"
```

Record that tag with the last deployment record; the running container's image
ID is authoritative even if the local checkout has since changed. On a first
installation there is no old running image to tag. Take the manual recovery
backup described in `sites/wishlist/docs/deployment/recovery.md` before changes
whose data cannot be recreated.

```bash
git status --short
git pull --ff-only
git submodule sync --recursive
git submodule update --init --recursive
git submodule status sites/wishlist
docker compose config --quiet
docker compose build wishlistweb
docker compose stop wishlistweb wishlistworker
docker compose run --rm --no-deps --pull never wishlistweb ./bin/rails db:prepare
docker compose up -d --no-build --pull never --wait --wait-timeout 120 wishlistweb wishlistworker
docker compose ps wishlistdb wishlistweb wishlistworker
```

If preparation fails, inspect that error before starting services against a
partially changed schema. For an app-only update Nginx need not be rebuilt: it
proxies assets from Rails and refreshes the backend's address through Docker DNS.
Rebuild/recreate it separately when its Dockerfile or config changes:

```bash
docker compose build nginx
docker compose up -d --no-build --no-deps nginx
docker compose exec -T nginx nginx -t
```

Run the optional checks below as appropriate after deployment. Existing settings
changes require container recreation, not just a process restart:

```bash
docker compose up -d --no-build --pull never --no-deps --force-recreate --wait --wait-timeout 120 wishlistweb wishlistworker
```

## 8. Optional smoke checks

These commands are documented for future deployments; they have not been rerun
against the live family installation as part of writing this guide. HTTP and
database checks below are read-only. The manual workflow test creates real data
and sends real mail, so use accounts/mailboxes you control or consenting testers.

### Containers, schemas and actual database connections

```bash
docker compose ps -a nginx wishlistdb wishlistweb wishlistworker
docker compose exec -T wishlistweb ./bin/rails db:version
docker compose exec -T wishlistweb ./bin/rails runner - <<'RUBY'
require "pg"
ActiveRecord::Base.configurations.configs_for(env_name: "production").each do |config|
  settings = config.configuration_hash
  PG.connect(host: settings[:host], port: settings[:port], user: settings[:username],
    password: settings[:password], dbname: settings[:database]) do |connection|
    raise "database check failed" unless connection.exec("SELECT 1").getvalue(0, 0) == "1"
  end
  puts "#{config.name}: connected"
end
RUBY
```

Expect all four connections to succeed; schema versions advance with future
migrations. `/up` establishes that Rails responds, not database/queue readiness.

### Native dependencies and temporary files

This optional one-off check loads native gems and writes only to its temporary
container filesystem; it does not connect to the database or deliver email:

```bash
docker compose run --rm --no-deps --pull never wishlistweb \
  bundle exec ruby -ropenssl -rpg -rvips -rtmpdir -e '
    puts RUBY_DESCRIPTION
    puts "UID: #{Process.uid}"
    puts OpenSSL::OPENSSL_VERSION
    puts "libpq: #{PG.library_version}"
    puts "libvips: #{Vips.version_string}"
    abort "unexpected runtime user" unless Process.uid == 1000
    Thread.new { puts "Ruby thread OK" }.join
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "probe"), "ok")
      puts "Temporary directory/write OK"
    end
  '
```

Expect the versions selected by the image, UID 1000 and both OK messages. This
would have detected the old host's seccomp/thread/filesystem-check failures.

### Internal and public HTTP, certificates and static assets

```bash
docker compose exec -T wishlistweb curl --fail --silent --show-error http://127.0.0.1:3000/up
docker compose exec -T wishlistweb curl --fail --silent --show-error -o /dev/null -w '%{http_code}\n' -H 'Host: mywishlist.top' http://127.0.0.1:3000/login
curl --fail --head http://mywishlist.top/login
curl --fail --head https://mywishlist.top/login
curl --fail --silent --show-error https://mywishlist.top/up
docker compose exec -T nginx nginx -t
docker compose exec -T nginx certbot certificates
```

Check both CSS and JavaScript against the running image's exact asset digests:

```bash
(
  set -e
  for asset in application.css application.js; do
    asset_path=$(docker compose exec -T wishlistweb ruby -rjson -e \
      'puts JSON.parse(File.read("public/assets/.manifest.json")).fetch(ARGV.fetch(0)).fetch("digested_path")' "$asset")
    curl --fail --silent --show-error --head "https://mywishlist.top/assets/$asset_path"
  done
)
```

Expect HTTPS 200, a stylesheet/JavaScript Content-Type and long-lived cache
headers for these fingerprinted assets. The block stops if a manifest entry or
download fails. In a browser, check the
Network/Console panels and exercise one Turbo form and a Stimulus interaction,
such as reordering your test list. Successful asset downloads alone do not prove
all browser behavior works. Do not add `curl -k` to bypass certificate validation.

### Queue readiness, failures and email delivery

```bash
docker compose exec -T wishlistworker ./bin/rails runner - <<'RUBY'
SolidQueue::Process.order(:kind, :name).pluck(:kind, :name, :last_heartbeat_at).each do |row|
  puts row.join(" | ")
end
raise "no recent worker heartbeat" unless SolidQueue::Process.where(kind: "Worker")
  .where("last_heartbeat_at > ?", 2.minutes.ago).exists?
puts "Ready: #{SolidQueue::ReadyExecution.count}"
puts "Scheduled: #{SolidQueue::ScheduledExecution.count}"
puts "Claimed: #{SolidQueue::ClaimedExecution.count}"
puts "Failed: #{SolidQueue::FailedExecution.count}"
RUBY
docker compose logs --tail=0 -f wishlistworker
```

Stop following with Ctrl-C. A recent heartbeat establishes a live worker;
processing an actual job establishes more. To test through the application:

1. Send an invitation to an agreed test mailbox; watch InvitationNotificationJob
   execute without a delivery exception.
2. Confirm inbox arrival (and Resend delivery details if needed). The link must
   use `https://mywishlist.top/`. A successful job means SMTP accepted delivery,
   not that the message reached the inbox.
3. Accept in a separate browser/session, create the account, verify friendship
   and the welcome email. An already-signed-in inviter takes a different path.
4. Test an existing-account invitation separately if that path changed.
5. For relevant releases, check friendship request/acceptance and password-reset
   email flows too. Use the UI so all mail still goes through jobs.

Optional application spot checks with dedicated test lists/items:

- Owner creates/edits a list/item and sees validation errors in the correct form.
- Accepted friend sees Friends lists; Private lists stay inaccessible, including
  by a direct saved URL. An unrelated account has no access.
- Friend records/edits/deletes an unrevealed purchase; the owner cannot see its
  secret details. Check a reveal boundary only on deliberate test data.
- Invitation cancellation invalidates that test link; accepting another invite
  establishes only the intended friendship; removing friendship revokes access.

Use UI cleanup for test data. Run automated Rails/system tests in the development
test environment, not against the production databases.

## 9. Inspect and troubleshoot

### Logs and container health

```bash
docker compose logs --since=15m --tail=200 nginx wishlistweb wishlistworker wishlistdb
docker compose logs --tail=0 -f wishlistworker
docker compose logs --since=15m --timestamps wishlistweb
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q wishlistweb)"
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q wishlistdb)"
docker inspect --format 'Status={{.State.Status}} Exit={{.State.ExitCode}} OOM={{.State.OOMKilled}} Restarts={{.RestartCount}}' "$(docker compose ps -a -q wishlistworker)"
```

Inspect specific fields, rather than printing full environment-bearing container
configuration. Health output includes recent probe results. Docker does not
restart an unhealthy container automatically; restart policies act on process
exit. `depends_on: service_healthy` coordinates Compose startup, not ongoing
dependency recovery after a host/daemon restart.

### Rails console and one-off commands

```bash
docker compose exec wishlistweb ./bin/rails console
docker compose run --rm --no-deps wishlistweb ./bin/rails console
```

`exec` uses a running container; `run` creates a one-off container from current
Compose/image/settings. `run` does not publish service ports. Use it to diagnose
startup failure or run preparation; `--no-deps` assumes the database is already
running. It still has production write access.

### Failed jobs

List IDs/classes without dumping serialized arguments or invitation/reset tokens:

```bash
docker compose exec -T wishlistworker ./bin/rails runner - <<'RUBY'
SolidQueue::FailedExecution.includes(:job).order(id: :desc).limit(10).each do |failure|
  puts [failure.id, failure.job.class_name, failure.exception_class].join(" | ")
end
RUBY
```

Open a console, inspect one failure privately, fix its cause, and retry only that
job if appropriate. Substitute a real failure ID:

```ruby
failure = SolidQueue::FailedExecution.find(123)
puts failure.message
failure.retry
```

Before retrying an email after a timeout, check Resend/inbox delivery to avoid a
duplicate. There is no blanket SMTP retry policy in ApplicationJob. Invitation
jobs skip invitations that have since been cancelled or accepted.

`SolidQueue::RecurringJob` once each hour at minute 12 is expected maintenance,
clearing completed execution history older than the retention period. It logs
enqueue/start/finish separately. Inspect its configured schedule and recent runs:

```bash
docker compose exec -T wishlistworker ./bin/rails runner - <<'RUBY'
require "pp"
pp SolidQueue::RecurringTask.pluck(:key, :schedule)
pp SolidQueue::RecurringExecution.where(task_key: "clear_solid_queue_finished_jobs")
  .order(run_at: :desc).limit(3).pluck(:run_at)
RUBY
```

### Database errors

```bash
docker compose exec -T wishlistdb sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT current_user, current_database();"'
docker compose exec -T wishlistweb sh -c 'printf "Host=%s User=%s Database=%s\n" "$WISHLIST_DATABASE_HOST" "$WISHLIST_DATABASE_USERNAME" "$WISHLIST_DATABASE"'
```

Single quotes make variable expansion happen inside the container. A local
`echo $WISHLIST_DATABASE_HOST` checks your shell, not the container settings.
For password-authentication failure, compare role/name/password settings and
remember that `POSTGRES_*` only initializes an empty volume. A succeeding local
socket connection alone does not prove password authentication works. To change
an existing role password, connect as its bootstrap superuser:

```bash
docker compose exec wishlistdb sh -c 'psql -U "$POSTGRES_USER" -d postgres'
```

In psql, list roles with `\du` and use `\password wishlist` with the actual role
name. The password prompt avoids a plaintext password in SQL history. Update
both env files to match and recreate application containers. If POSTGRES_USER
itself was edited after initialization, connect using the original role name.
Do not delete the data volume to fix credentials.

### DNS, certificate and proxy errors

```bash
dig +short A mywishlist.top
dig +short AAAA mywishlist.top
rancher-machine ip "$WISHLIST_MACHINE"
docker compose exec -T nginx nginx -t
docker compose logs --since=15m --tail=100 nginx
docker compose exec -T nginx certbot certificates
```

No valid A/AAAA record means fix DNS first. Connection timeouts mean check
ports/firewalls/reachability. A first-run missing-key warning is expected until
issuance; HTTPS remains disabled if validation fails. A 502 after HTTPS works
means investigate the backend/web logs and readiness. A 403 with a host-blocking
message means check WISHLIST_HOST and forwarded headers. Missing assets mean
check the manifest and the running image, not a separate Nginx public directory.

After fixing DNS/reachability, wake the image's renewal loop instead of waiting
12 hours or repeatedly forcing new production certificates:

```bash
docker compose kill -s HUP nginx
docker compose logs --tail=50 -f nginx
```

Optional renewal rehearsal (contacts Let's Encrypt staging and needs public port
80; this is not part of every routine deployment):

```bash
docker compose exec nginx certbot renew --cert-name mywishlist.top --dry-run
```

Keep nginx_secrets across recreations; do not delete it to renew a certificate.

### Expired Rancher Machine certificates

If TLS fails before Docker commands can connect:

```bash
rancher-machine regenerate-certs --client-certs "$WISHLIST_MACHINE"
eval "$(rancher-machine env "$WISHLIST_MACHINE")"
docker info --format 'Name={{.Name}} Version={{.ServerVersion}}'
docker compose up -d --no-build --wait --wait-timeout 180 wishlistdb wishlistweb wishlistworker nginx
docker compose ps -a nginx wishlistdb wishlistweb wishlistworker
```

Regeneration can restart Docker and interrupt containers. Inspect readiness
afterward; if Rails/worker failed while PostgreSQL started, inspect logs and
restart just those services once the DB is healthy. A hostname/local Machine
alias change is separate from certificates/provider metadata; preserve shared
CA/client material when moving or renaming local registrations.

### Capacity and disk usage

```bash
docker stats --no-stream
docker system df
docker system df -v
docker compose exec -T wishlistweb du -sh /rails/storage
rancher-machine ssh "$WISHLIST_MACHINE" 'free -h'
rancher-machine ssh "$WISHLIST_MACHINE" 'df -h /'
rancher-machine ssh "$WISHLIST_MACHINE" 'uptime'
rancher-machine ssh "$WISHLIST_MACHINE" 'vmstat 1 10'
```

Use `docker stats` interactively in another terminal while building if observing
peaks; Ctrl-C ends the display. It does not measure every short-lived peak or
the whole host's memory. JSON logs rotate at roughly 10 MB x 3 per container;
application-written files need their own rotation. Manual unused-image cleanup:

```bash
docker image prune
```

This removes dangling images, not volumes. Keep tagged rollback images; do not
turn volume pruning into routine disk maintenance or manually edit Docker's
storage directories.

## 10. Restart, recreate and rollback

Restart existing processes without applying image/env changes:

```bash
docker compose restart wishlistweb wishlistworker
```

Apply changed environment files or force replacement using the existing image:

```bash
docker compose up -d --no-deps --no-build --pull never --force-recreate --wait --wait-timeout 120 wishlistweb wishlistworker
```

Optional persistence/restart check during a maintenance window: note a dedicated
test list/item, force-recreate the application containers, and confirm it remains.
For a full stack restart, stop just these services and start DB/app before nginx:

```bash
docker compose stop nginx wishlistweb wishlistworker wishlistdb
docker compose up -d --no-build --wait --wait-timeout 180 wishlistdb wishlistweb wishlistworker nginx
```

This intentionally interrupts the site. No volumes are removed. Recovery after
an actual droplet reboot can be checked the same way once SSH/Docker reconnect.

For a code rollback, first review database compatibility: restoring an old image
does not reverse migrations or env edits. If compatible, select the saved tag:

```bash
WISHLIST_ROLLBACK_IMAGE=wishlist:rollback-REPLACE_WITH_SAVED_TIMESTAMP
docker image inspect "$WISHLIST_ROLLBACK_IMAGE" --format '{{.Id}}'
docker image tag "$WISHLIST_ROLLBACK_IMAGE" wishlist:production
docker compose up -d --no-deps --no-build --pull never --force-recreate --wait --wait-timeout 120 wishlistweb wishlistworker
docker compose ps wishlistweb wishlistworker
```

Restore corresponding runtime settings if they changed and record the rollback.
Before another build, restore the reviewed source revision too; otherwise it
would rebuild the failing code. Do not run a generic `db:rollback` or restore a
database over newer family data without a separate recovery decision. Nginx
configuration rollback is a separate checkout/build/recreate of nginx only.

## 11. Record the deployed revision and image

After a successful deployment, save a local record without copying env values:

```bash
WISHLIST_DEPLOY_ID=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p deployment-records
{
  date -u
  printf 'Machine: %s\n' "$WISHLIST_MACHINE"
  rancher-machine ip "$WISHLIST_MACHINE"
  git rev-parse HEAD
  git -C sites/wishlist rev-parse HEAD
  docker info --format 'Name={{.Name}} Version={{.ServerVersion}}'
  docker compose images nginx wishlistweb wishlistworker wishlistdb
  docker inspect --format 'Web image ID={{.Image}}' "$(docker compose ps -q wishlistweb)"
  docker inspect --format 'Proxy image ID={{.Image}}' "$(docker compose ps -q nginx)"
  docker compose exec -T wishlistweb ./bin/rails db:version
} > "deployment-records/wishlist-$WISHLIST_DEPLOY_ID.txt"
```

Also note the rollback tag, 1Password item names, local env-file paths, which
checks were performed, any skipped checks, and externally observed failures.
Do not put secret values into that record. Preserve the parent commit/submodule
pointer in Git so the source can be reconstructed on another computer.

## References

- Docker Compose: [up](https://docs.docker.com/reference/cli/docker/compose/up/), [run](https://docs.docker.com/reference/cli/docker/compose/run/), [config](https://docs.docker.com/reference/cli/docker/compose/config/)
- [Nginx/Certbot operations](https://github.com/JonasAlfredsson/docker-nginx-certbot/blob/master/docs/advanced_usage.md)
- [Solid Queue](https://github.com/rails/solid_queue/tree/v1.6.0)
