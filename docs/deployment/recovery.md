# Manual Wishlist backup and recovery

These procedures complement the deployment runbook. They document manual
recovery; automated backup scheduling and a real restore rehearsal remain future
work. They were not run against the live family installation while writing them.
All commands run locally from the `dynamic_sites` root, with Rancher Machine
selecting the intended remote host. Redirection writes backup files locally.

Rebuilding source/images alone cannot restore accounts, lists, purchases or
invitations. Keep the database dumps, any uploaded files, production signing
secret, runtime settings, and the parent/submodule revisions. Certificates can
be reissued, but preserving nginx_secrets also retains the ACME account and
existing certificate. Named volumes disappear with a destroyed droplet.

## Take a consistent manual backup

Select and verify the existing source host using runbook section 3. The example
database stem is the actual current `wishlist_production`; change it only if your
runtime configuration uses a different name. Check `db:version` before stopping
the application. Save runtime secret values separately in 1Password.

```bash
docker compose exec -T wishlistweb ./bin/rails db:version
WISHLIST_DATABASE_NAME=wishlist_production
umask 077
WISHLIST_BACKUP_DIR="$HOME/wishlist-backups/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$WISHLIST_BACKUP_DIR"
docker compose stop nginx wishlistweb wishlistworker
```

This deliberately takes the site offline. PostgreSQL stays running; stopped
web/worker prevent application writes across the four dumps and storage archive.
The parenthesized block below stops on the first failed backup command. If it
fails, do not treat the directory as a complete backup; fix the error or restart
the services explicitly when abandoning the attempt.

```bash
(
  set -e
  for suffix in '' _cache _queue _cable; do
    database="$WISHLIST_DATABASE_NAME$suffix"
    docker compose exec -T wishlistdb sh -c \
      'exec pg_dump --format=custom -U "$POSTGRES_USER" -d "$1"' \
      sh "$database" > "$WISHLIST_BACKUP_DIR/$database.dump"
  done

  docker compose run --rm --no-deps --pull never -T --entrypoint tar \
    wishlistweb -C /rails/storage -czf - . \
    > "$WISHLIST_BACKUP_DIR/storage.tar.gz"
  docker compose run --rm --no-deps --pull never -T --entrypoint tar \
    nginx -C /etc/letsencrypt -czf - . \
    > "$WISHLIST_BACKUP_DIR/letsencrypt.tar.gz"

  {
    date -u
    printf 'Machine: %s\nDatabase stem: %s\n' "$WISHLIST_MACHINE" "$WISHLIST_DATABASE_NAME"
    git rev-parse HEAD
    git -C sites/wishlist rev-parse HEAD
    docker compose images nginx wishlistweb wishlistworker wishlistdb
  } > "$WISHLIST_BACKUP_DIR/revisions.txt"

  cd "$WISHLIST_BACKUP_DIR"
  sha256sum ./*.dump storage.tar.gz letsencrypt.tar.gz > SHA256SUMS
  printf 'All backup commands completed.\n' > COMPLETE
)
```

The helper containers override the image entrypoint with tar; they do not start
Rails, Certbot or published service ports. Their volumes are the same volumes
used by the stopped services. PostgreSQL dumps use the matching server's tools,
and do not rely on raw copies of a running PostgreSQL data directory.

Check the result, then resume the source site:

```bash
cat "$WISHLIST_BACKUP_DIR/COMPLETE"
(cd "$WISHLIST_BACKUP_DIR" && sha256sum --check SHA256SUMS)
ls -lh "$WISHLIST_BACKUP_DIR"
docker compose up -d --no-build --pull never --wait --wait-timeout 180 wishlistdb wishlistweb wishlistworker nginx
```

Checksums detect transfer damage, not whether a dump restores successfully.
Keep a further off-computer copy in secure storage; the archives contain family
data and private TLS keys. Compression and file permissions do not encrypt them.
Preserve the matching SECRET_KEY_BASE and other runtime settings in 1Password.

## Restore onto a fresh replacement droplet

This section replaces the named databases from the archives. Use it only on the
new, empty recovery host, with no family traffic or application workers running.
Do not run it against the existing live deployment.

1. Create a new droplet under an unused Machine name, for example
   `dynamicsites-recovery`, using runbook section 2 with that name substituted.
2. Select it with `WISHLIST_MACHINE=dynamicsites-recovery`, clear stale Docker
   overrides, and evaluate `rancher-machine env` as in section 3. Verify its IP
   and Docker endpoint. Keep the old host available if it still exists.
3. Clone/check out the recorded parent revision and its pinned submodules.
   Restore untracked runtime files from 1Password. Use the original signing
   secret; the DB username/password must match the newly initialized instance.
4. Build the recorded application/proxy and start PostgreSQL only. Do not run
   `db:prepare`, web or worker yet.

Example source checkout after reviewing the revision in `revisions.txt`:

```bash
git status --short
git switch --detach RECORDED_PARENT_COMMIT
git submodule update --init --recursive
docker compose config --quiet
docker compose build wishlistweb nginx
docker compose up -d --wait --wait-timeout 120 wishlistdb
docker info --format 'Name={{.Name}} Version={{.ServerVersion}}'
```

Set the actual local backup directory, check it, and restore all four databases:

```bash
WISHLIST_BACKUP_DIR="$HOME/wishlist-backups/REPLACE_WITH_BACKUP_TIMESTAMP"
WISHLIST_DATABASE_NAME=wishlist_production
cat "$WISHLIST_BACKUP_DIR/COMPLETE"
(cd "$WISHLIST_BACKUP_DIR" && sha256sum --check SHA256SUMS)
```

Stop if checksum verification fails. After rechecking that Docker targets the
fresh recovery host, run:

```bash
(
  set -e
  for suffix in '' _cache _queue _cable; do
    database="$WISHLIST_DATABASE_NAME$suffix"
    docker compose exec -T wishlistdb sh -c \
      'exec pg_restore -U "$POSTGRES_USER" --dbname=postgres --clean --if-exists --create --no-owner --no-acl --exit-on-error' \
      < "$WISHLIST_BACKUP_DIR/$database.dump"
  done

  docker compose run --rm --no-deps --pull never -T --entrypoint tar \
    wishlistweb -C /rails/storage -xzf - \
    < "$WISHLIST_BACKUP_DIR/storage.tar.gz"
  docker compose run --rm --no-deps --pull never -T --entrypoint tar \
    nginx -C /etc/letsencrypt -xzf - \
    < "$WISHLIST_BACKUP_DIR/letsencrypt.tar.gz"
)
```

`pg_restore --create` uses the database names stored inside the archives.
`--clean` replaces those databases, including the empty primary database created
by the image; the connection to `postgres` is only for creating/dropping them.
`--no-owner --no-acl` assigns restored objects to the bootstrap login on the new
instance instead of requiring the old roles. This assumes the current dedicated,
single-login deployment. Restore on PostgreSQL 18 first; a major upgrade is a
separate operation.

With the intended source revision and runtime settings in place:

```bash
docker compose run --rm --no-deps --pull never wishlistweb ./bin/rails db:prepare
docker compose run --rm --no-deps --pull never wishlistweb ./bin/rails db:version
docker compose run --rm --no-deps --pull never wishlistweb ./bin/rails runner \
  'puts "Users=#{User.count} Lists=#{List.count} Items=#{ListItem.count}"; puts "Queued=#{SolidQueue::ReadyExecution.count} Failed=#{SolidQueue::FailedExecution.count}"'
```

Review restored queue state before starting workers: a backup may contain pending
email jobs, which will resume processing. The database should contain the expected
family accounts and lists; do not bootstrap a duplicate owner account.

Update the domain A/AAAA records and firewall access for the new host. Then:

```bash
docker compose up -d --no-build --pull never --wait --wait-timeout 180 wishlistweb wishlistworker nginx
docker compose ps nginx wishlistdb wishlistweb wishlistworker
curl --fail --head https://mywishlist.top/login
```

Run the readiness/assets/worker checks in the runbook and confirm a known account,
list, and any uploaded file work. Existing valid certificates can be reused for
the same domain; expired/missing certificates require successful public DNS and
HTTP-01 issuance. Automatic backups and a rehearsed restore are not established
merely by having these instructions.

## References

- [PostgreSQL pg_dump](https://www.postgresql.org/docs/18/app-pgdump.html)
- [PostgreSQL pg_restore](https://www.postgresql.org/docs/18/app-pgrestore.html)
- [Docker volume backup/restore](https://docs.docker.com/engine/storage/volumes/#back-up-restore-or-migrate-data-volumes)
