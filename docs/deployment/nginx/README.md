# Wishlist HTTPS proxy

This configuration is for the new `dynamicsites-next` host. Copy
`Dockerfile` and `mywishlist.conf` into `dynamic_sites/config/nginx/`, then
replace that parent's `nginx` service with the definition in `compose.nginx.yml`.
Keep its existing top-level `nginx_secrets:` volume declaration. These are
reviewable examples; the assistant has not edited the parent deployment repo.

The current parent Dockerfile builds only Wishlist's proxy; retain the old
sites' definition in Git while their old host still serves them. Its build context is the parent repository,
so the COPY source starts with `config/nginx`. Configuration is copied into the
image rather than bind-mounted from a path that would need to exist remotely.

## How the configuration works

The image is pinned to `jonasal/nginx-certbot:6.2.0-nginx1.31.8-alpine`, replacing
the old 0.14 base. Its existing port-80 server answers HTTP-01 certificate
challenges and redirects other HTTP requests to HTTPS. Preserve that built-in
configuration by adding our file under `/etc/nginx/user_conf.d`, which the image
links into its active config directory. Do not mount over `/etc/nginx/conf.d`.

The image discovers the domain from `server_name` and the certificate name from
the `ssl_certificate_key` path. At first startup it can temporarily disable the
HTTPS configuration while obtaining the missing certificate, leaving HTTP
available for the challenge, then enable HTTPS. The certificate files and renewal
state survive container replacement in `nginx_secrets`. They are not copied from
the old server. `CERTBOT_EMAIL` is the existing forwarding address; change it if
you prefer another operational contact. Renewal checks run every 12 hours.

Our server listens on HTTPS, enables HTTP/2, and allows TLS 1.2/1.3. The session
cache permits session reuse; session tickets are disabled. TLS 1.2 uses the
current TLSRef Intermediate ECDHE/AEAD cipher list, with client preference.
TLS 1.3 retains its library defaults; custom DH parameters are unnecessary.
Rails already manages its HSTS and other response
headers. Nginx's normal access/error logs use the image's stdout/stderr paths,
covered by the Compose logging limits.

`proxy_pass` sends every application and asset request to Rails. Assets remain
inside the Rails image; no second copy of `public/assets` is needed in Nginx.
The Host and forwarded-host headers preserve the public hostname, forwarded-proto
tells Rails the visitor used HTTPS, and forwarded-for records the visitor IP.
This assumes Nginx is directly exposed to visitors; it overwrites client-supplied
forwarding headers. If a CDN/proxy is introduced later, revisit how the client
address is obtained.

`wishlistweb` is the Compose service name. Docker's embedded DNS at `127.0.0.11`
resolves it inside the shared network. `resolve` refreshes that address with a
10-second DNS validity period, and `zone` supplies the shared upstream state
required for dynamic resolution. This lets Nginx recover after recreating Rails
without requiring a proxy restart just because the container IP changed.
The pinned Nginx release supports this in its open-source build.

## DNS and public access

Get the **new** host's address:

```sh
rancher-machine ip dynamicsites-next
```

In Namecheap, set the `@` A record for `mywishlist.top` to that address, replacing
any parking A record. Remove conflicting root URL-redirect records. If a root
AAAA record exists, it must point to working IPv6 on this host; otherwise remove
that record so certificate validation and visitors do not reach another host.
Leave the email MX/TXT/DKIM records alone. No `www` record or certificate is
required by this configuration.

If a DigitalOcean Cloud Firewall or host firewall is enabled, allow inbound TCP
80 and 443. Keep SSH and the existing secured Docker API access working. Rails
and PostgreSQL do not need published ports.

Confirm public DNS resolves to the new address before starting certificate
issuance, for example with `dig +short A mywishlist.top`. Namecheap's control
panel displaying the new value does not establish public DNS propagation.

## Build, start and verify

From the parent repository targeting the new host:

```sh
eval "$(rancher-machine env dynamicsites-next)"
docker info --format 'Name={{.Name}} Version={{.ServerVersion}}'
docker compose config --quiet
docker compose build nginx
docker compose up -d nginx
docker compose logs --tail=100 -f nginx
```

Wait for certificate issuance/configuration and Nginx reload to succeed; use
Ctrl-C to stop following logs (the container continues running). `STAGING=0`
requests a real certificate. Our local validation uses the image's local test CA
and does not contact Let's Encrypt; actual issuance remains a
live deployment check. If issuance fails, diagnose DNS/port access from its logs
before repeatedly retrying.

Then run:

```sh
docker compose exec nginx nginx -t
curl -I http://mywishlist.top/login
curl -I https://mywishlist.top/login
curl --fail --silent --show-error https://mywishlist.top/up
```

Expect an HTTP-to-HTTPS redirect, HTTPS 200 for login, and the green health page.
The HTTPS checks deliberately use normal certificate verification. Inspect the
login page in a browser and confirm CSS/JavaScript load. Starting Nginx may start
its declared Wishlist dependencies, but no old application services are needed.

## Later updates

After editing the copied Nginx configuration, rebuild and recreate only nginx.
Persist `/etc/letsencrypt` across deployments. Do not delete its volume to renew
a certificate. Updating the shared Rails image and recreating its services does
not normally require rebuilding Nginx.

## Local validation completed

The pinned image pulled and the Dockerfile built successfully on Docker Desktop.
An isolated network with no published ports exercised the image's normal startup
in `USE_LOCAL_CA=1` test mode. It generated a test certificate, enabled the HTTPS
configuration and passed `nginx -t`. HTTP redirected with its path/query intact;
an HTTPS client trusted only the test CA and reached the temporary backend with
the expected host/protocol/client headers. Forged incoming forwarding headers
were overwritten. Switching to a different backend IP recovered through Docker
DNS without restarting Nginx. The temporary containers and certificate volume
were removed afterward. Public DNS, Let's Encrypt issuance and proxying to the
actual droplet remain unverified.

References:

- [Image tags](https://github.com/JonasAlfredsson/docker-nginx-certbot/blob/master/docs/dockerhub_tags.md)
- [Image startup/configuration conventions](https://github.com/JonasAlfredsson/docker-nginx-certbot/blob/master/docs/good_to_know.md)
- [Image startup script](https://github.com/JonasAlfredsson/docker-nginx-certbot/blob/master/src/scripts/start_nginx_certbot.sh)
- [Dynamic upstream resolution](https://nginx.org/en/docs/http/ngx_http_upstream_module.html#server)
- [TLSRef Intermediate cipher policy](https://docs.tlsref.org/server-side-tls.html#intermediate-compatibility-recommended)
