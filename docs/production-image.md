# Production image and compatibility check

`Dockerfile.production` builds the image shared by the future web and Solid Queue
worker services. It uses Ruby 4.0.6 on Debian Bookworm, matching the application's
Ruby version while selecting an explicit distribution rather than a moving slim
tag. This does not guarantee compatibility with the old droplet's kernel/runtime.

The image:

- Installs gems from Gemfile.lock, excluding development and test groups.
- Uses one compilation job to limit build-time memory pressure.
- Includes PostgreSQL, OpenSSL, libvips, and jemalloc runtime dependencies.
- Precompiles Bootsnap and assets without a database or production credentials.
- Runs as the rails user (UID/GID 1000).
- Starts Puma on port 3000; the existing Nginx proxy will terminate public HTTPS.
- Can run `./bin/jobs` instead of the default command for the separate worker.
- Does not run migrations automatically. Run `./bin/rails db:prepare` once before
  starting production web/worker services, using the eventual runtime settings.

The unused scaffold `bin/docker-entrypoint` still contains automatic migration
logic, but this image does not use that entrypoint. Thruster remains in the
application's existing bundle but is not started; the existing Nginx proxy serves
that role. No additional reverse proxy is required inside this image.

## Build locally

From the Wishlist checkout, using a local Docker daemon:

```sh
docker info --format 'Name={{.Name}} Version={{.ServerVersion}} OS={{.OperatingSystem}}'
docker build -f Dockerfile.production -t wishlist:production-check .
```

When used as a submodule, set the build context to `./sites/wishlist` and the
Dockerfile to `Dockerfile.production` relative to that context. The Wishlist
`.dockerignore` then applies. It excludes environment files, credential keys,
Git metadata, and local AWS/Codex/agent directories. Supply deployment credentials
at runtime rather than through build arguments or copied environment files.

`config/database.yml` currently evaluates ENV.fetch for every Rails environment,
including test settings during production boot. The asset-build step supplies
explicit non-secret placeholders only for that command. They do not become
runtime ENV defaults. Runtime environment configuration will need to account for
this behavior; do not copy the build placeholders into real production database
settings. The production configuration and SMTP settings are a separate next step.

## Local verification completed

The image was built on Docker Desktop 28.3.2, Linux x86_64. Docker reports an image
size of 231,710,792 bytes (approximately 232 MB). With disposable, network-isolated
containers and fake settings:

- Ruby threads, OpenSSL, PostgreSQL native bindings, and libvips loaded.
- Execution used UID 1000.
- Selected development/test gems and private local paths were absent.
- Rails 8.1.3.1 booted in production with Solid Queue configured and assets present.
- Puma returned HTTP 200 for `/up` and a precompiled stylesheet, using HTTPS proxy
  headers. The web container published no host ports and was removed afterward.

These checks did not use a production database, send email, run the queue worker
against a database, or establish compatibility with the remote host.

## First checks on the existing droplet

Run these from the local Wishlist checkout in the deployment shell. Rancher
Machine selects the remote daemon; confirm the server version before continuing.

```sh
eval "$(rancher-machine env dynamicsites)"
docker version
```

The expected remote server is Docker 19.03.2/API 1.40, not Docker Desktop. The
current host kernel is 4.4.0-210. First run two disposable base-image checks, without
published ports, host mounts, or existing production database access:

```sh
docker run --rm --network none ruby:4.0.6-slim-bookworm \
  ruby -ropenssl -e 'puts RUBY_DESCRIPTION; puts OpenSSL::OPENSSL_VERSION; Thread.new { puts "Ruby thread OK" }.join'

docker run --rm --network none postgres:18.4-bookworm postgres --version
```

These commands may download the base images. The PostgreSQL version check does
not initialize or start a database and is not a full PostgreSQL startup test.
Capture any failure before trying alternative security/runtime settings. Do not
change the daemon configuration or disable its security profile as a blanket fix.

If both checks pass, build the application image on the droplet using the existing
classic-builder workflow:

```sh
DOCKER_BUILDKIT=0 docker build -f Dockerfile.production -t wishlist:production-check .
```

No application services are started or recreated by this build. Observe memory
and disk during compilation from a second SSH session, then record the result:

```sh
free -h
df -h /
docker image inspect wishlist:production-check --format 'Size={{.Size}} User={{.Config.User}}'
```

Remote production boot, a disposable PostgreSQL startup test, worker/database
integration, and runtime resource measurements follow after the image passes
this compatibility gate. Keep the existing sites and their volumes untouched.
