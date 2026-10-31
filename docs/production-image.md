# Production image and compatibility check

`Dockerfile.production` builds the image shared by the future web and Solid Queue
worker services. It uses Ruby 4.0.6 on Alpine 3.24, matching the application's
Ruby version and selecting an explicit Alpine release. The user confirmed that
this base image creates threads on the old droplet with default seccomp enabled.
Full application and PostgreSQL compatibility still need remote verification.

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

The Alpine image was built on Docker Desktop 28.3.2, Linux x86_64. Docker reports
168,087,970 bytes (approximately 168 MB), compared with approximately 232 MB for
the original Bookworm image. With disposable, network-isolated containers and
fake settings, the Alpine checks passed:

- Ruby threads, OpenSSL, PostgreSQL native bindings, and libvips loaded.
- Execution used UID 1000.
- Selected development/test gems and private local paths were absent.
- Rails 8.1.3.1 booted in production with Solid Queue configured and assets present.
- Puma returned HTTP 200 for `/up` and a precompiled stylesheet, using HTTPS proxy
  headers. The web container published no host ports and was removed afterward.
- `./bin/jobs --help` loaded successfully without database access.

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

### If the old daemon rejects an OCI manifest

The actual Ruby pull failed on Docker 19.03.2 before Ruby started, reporting that
it expected application/vnd.docker.distribution.manifest.v2+json but received
application/vnd.oci.image.manifest.v1+json. This tests image-format compatibility,
not Ruby/kernel compatibility.

A local Buildx Docker-format export succeeded. The resulting amd64 archive is
`/tmp/wishlist-ruby-base-docker.tar` (about 81 MB), tagged
`ruby:4.0.6-slim-bookworm`; its embedded manifest is Docker schema 2. The user successfully loaded it on the old daemon. Ruby and OpenSSL started,
but Thread.new then failed with Operation not permitted. Repeating the test with
seccomp=unconfined succeeded, confirming the default seccomp profile blocks
thread creation. This was a diagnostic, not a production security setting.
No remote changes were
made by the assistant.

To regenerate that archive on local Docker Desktop (verify that `default` really
points to the local daemon):

```sh
docker --context default info --format 'Name={{.Name}} Version={{.ServerVersion}}'
mkdir -p /tmp/wishlist-base-export-context
printf '%s\n' 'FROM ruby:4.0.6-slim-bookworm' > /tmp/wishlist-base-export-context/Dockerfile
docker --context default buildx build --platform linux/amd64 --provenance=false \
  --output type=docker,dest=/tmp/wishlist-ruby-base-docker.tar \
  --tag ruby:4.0.6-slim-bookworm /tmp/wishlist-base-export-context
```

Then, in the local deployment shell targeting the droplet, load the local archive
through the remote Docker API and retry the Ruby check:

```sh
docker load -i /tmp/wishlist-ruby-base-docker.tar
docker run --rm --network none ruby:4.0.6-slim-bookworm \
  ruby -ropenssl -e 'puts RUBY_DESCRIPTION; puts OpenSSL::OPENSSL_VERSION; Thread.new { puts "Ruby thread OK" }.join'
```

This preserves the image contents while changing the distribution format. The
same conversion may be needed for PostgreSQL. A subsequent classic application
build should use the locally loaded Ruby tag; do not add --pull, which would
retry the incompatible registry manifest. No registry or host upgrade is needed
for this particular workaround, but old-runtime execution still needs testing.

### Alpine compatibility test

The user successfully ran the isolated thread test on the old droplet with
default seccomp enabled: Alpine 3.24.1, Ruby 4.0.6 with musl, OpenSSL 3.5.7,
and `Ruby thread OK`. The production Dockerfile now selects the release-specific
`ruby:4.0.6-alpine3.24` tag. It resolves to the same image as the tested
`ruby:4.0.6-alpine` tag (index digest
`sha256:6ec7aeb4f3f0b67a21fb73a83fc20a4055696e64b933229f68ec805a3de38fcc`).

`/tmp/wishlist-ruby-alpine-docker.tar` has been regenerated with the
`ruby:4.0.6-alpine3.24` tag (50,076,672 bytes). Load it again on the remote daemon
so the tag matches the Dockerfile and avoids an incompatible registry pull.

To reproduce the archive on local Docker Desktop:

```sh
mkdir -p /tmp/wishlist-alpine-export-context
printf '%s\n' 'FROM ruby:4.0.6-alpine3.24' > /tmp/wishlist-alpine-export-context/Dockerfile
docker --context default buildx build --platform linux/amd64 --provenance=false \
  --output type=docker,dest=/tmp/wishlist-ruby-alpine-docker.tar \
  --tag ruby:4.0.6-alpine3.24 /tmp/wishlist-alpine-export-context
```

In the local deployment shell targeting the droplet:

```sh
docker load -i /tmp/wishlist-ruby-alpine-docker.tar
docker run --rm --network none ruby:4.0.6-alpine3.24 \
  ruby -ropenssl -e 'puts File.read("/etc/alpine-release"); puts RUBY_DESCRIPTION; puts OpenSSL::OPENSSL_VERSION; Thread.new { puts "Ruby thread OK" }.join'
```

Keep default seccomp enabled. PostgreSQL compatibility still needs testing.

### Application build after compatibility checks

Once the selected base images pass and the Dockerfile matches them, build the application image on the droplet using the existing
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
