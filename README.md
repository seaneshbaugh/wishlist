# Wishlist

A self-hosted wishlist for family and friends, built with Ruby on Rails, Turbo,
and Stimulus. Users manage lists and items, and friends record purchases with a
reveal date so gifts stay a surprise. Authentication, JavaScript, and a modern
browser are required.

## Development setup

The development environment uses Docker Compose on Fedora and Ubuntu/WSL. Ruby,
Rails, PostgreSQL, and browser-test dependencies run in containers; you do not
need to install Ruby or Firefox on the host. Run the commands below from the
repository directory in your Linux shell, with Docker and Compose v2 available.

The repository currently uses Ruby 4.0.6, Rails 8.1, and PostgreSQL 18.4.

Create an untracked `.env` file in the repository root. These example credentials
are for local development only:

```dotenv
POSTGRES_DB=wishlist_development
POSTGRES_USER=wishlist
POSTGRES_PASSWORD=wishlist

WISHLIST_DATABASE=wishlist_development
WISHLIST_DATABASE_USERNAME=wishlist
WISHLIST_DATABASE_PASSWORD=wishlist
WISHLIST_DATABASE_HOST=db
WISHLIST_DATABASE_PORT=5432

WISHLIST_TEST_DATABASE=wishlist_test
WISHLIST_TEST_DATABASE_USERNAME=wishlist
WISHLIST_TEST_DATABASE_PASSWORD=wishlist
WISHLIST_TEST_DATABASE_HOST=db
WISHLIST_TEST_DATABASE_PORT=5432

DEVISE_MAILER_SENDER=owner@example.test
```

Keep the test database separate from development: tests replace its data. The
PostgreSQL container initializes its database/user/password from `POSTGRES_*`
only when its data volume is first created; editing `.env` does not change an
existing database role's credentials.

Build the web image, start PostgreSQL and Mailpit, prepare the development
schema, and start Rails:

```sh
docker compose build web
docker compose up -d db mailpit
docker compose run --rm web bundle exec rails db:prepare
docker compose up -d web
```

Wait for PostgreSQL to be ready before running `db:prepare`. Rails is available
at http://localhost:3000 and Mailpit at http://localhost:8025. The web container
runs `bin/dev`, including the Tailwind watcher. Inspect application logs with:

```sh
docker compose logs -f web
```

The Compose file bind-mounts this checkout into the container. Commands running
as root in the development container can create root-owned host files; restore
the affected files' ownership before editing them as your normal user. On Fedora,
bind-mount access also depends on the host's SELinux configuration. On WSL, run
these commands from Ubuntu with access to your Docker daemon.

## Create the first account

Signup requires an invitation, so create the first confirmed account in a Rails
console:

```sh
docker compose exec web bundle exec rails console
```

Use your own username and email address in this example. Usernames must start
with a letter and contain 4–32 letters, digits, or underscores.

```ruby
require "io/console"

user = User.new(username: "owner", email: "owner@example.test")
user.password = IO.console.getpass("Password: "); nil
user.password_confirmation = IO.console.getpass("Confirm password: "); nil
user.skip_confirmation!
user.save!
```

The password prompts hide input; `; nil` also prevents the console from echoing
the assigned passwords. `skip_confirmation!` sets confirmation before saving;
`save!` still runs normal validations. This account can sign in immediately and
send invitations. No bootstrap rake task is required.

For production, use `RAILS_ENV=production bin/rails console` in the deployed
environment after its databases and configuration are ready. Existing accounts
continue to work without retrospective invitations.

## Friends and list access

Lists marked **Friends** are visible only to accepted friends. **Private** lists
are owner-only; there are no anonymous public lists or global user directory.
Friendship is mutual and requires explicit acceptance. Removing friendship
revokes access to both people's lists and purchases on subsequent requests,
including purchases they previously made; it does not delete purchase history.

Use the Friends page to request friendship from an existing user by email.
Unknown addresses receive generic feedback, and there is no outgoing request
list. Friend requests and invitations are separate: requesting friendship does
not invite an unknown email to register.

## Invitations and registration

Every confirmed user can send invitations from **Invitations**. The page lists
their sent emails and pending/accepted status. Sending an invitation does not
create a placeholder user or establish friendship.

- New recipients choose a username and password. Acceptance creates a confirmed
  account and establishes friendship with the sender; no separate confirmation
  email is needed.
- Existing recipients sign in to the matching account, then explicitly accept
  friendship. A different signed-in account must switch accounts first.
- An existing unconfirmed account requires its password before invitation
  acceptance confirms its current email. Devise's lockout rules still apply;
  a pending email-address change is not confirmed by this flow.
- The sender sees consistent behavior for existing and new accounts. Inviting
  someone who is already a friend returns an explicit error. Recipient emails
  explain whether to register or sign in and that either person can later remove
  the friendship.
- Different people may invite the same email independently. Accepting one
  invitation befriends only its sender. Other invitations remain pending and can
  be accepted individually after registration.
- Invitations do not expire. Repeated submission reuses a pending invitation
  without sending another email. **Resend** sends it again using the same link.
- **Cancel invitation** deletes a pending invitation and invalidates its link.
  A later invitation gets a new identity; the old link remains invalid. Accepted
  invitations remain as history and cannot be resent or cancelled. Removing a
  friendship does not reactivate an accepted invitation.

Invitation links contain a signed token and are intended for the invited
mailbox. Opening a link is read-only; acceptance requires a form submission.
Neither `/register` nor its POST endpoint permits registration without a valid,
pending invitation. Tokens alone never authenticate an existing account or
change its password.

Deleting an account removes invitations it sent or accepted without deleting
other users' accounts. Invitation acceptance preserves any existing friendship
pair and establishes acceptance if the pair was pending.

For beta, invitations deliberately have no expiration, token rotation on resend,
sending limits, delivery tracking, or acceptance-notification email. Invitations
are not automatically sent from the friend-request form. An interactive bootstrap
task can be added later if useful.

## Background email and workers

All email delivery runs in Active Job, after the relevant transaction commits.
Invitation and friendship jobs skip records that were deleted or resolved before
execution. Delivery failure does not undo an invitation or friendship.

| Email | Queue |
| --- | --- |
| Invitations and resends | `invitation_notification` |
| Friendship requests and acceptance | `friendship_notification` |
| New-account notification | `registration_notification` |
| New-account welcome | `registration_welcome` |
| Devise confirmation, password recovery, and unlock instructions | `default` |

New invitation registrations enqueue the registration and welcome jobs.
Acceptance by an existing account sends neither those jobs nor duplicate
friendship notifications. Currently, new-account notifications go to the user
whose email matches `DEVISE_MAILER_SENDER`; there is no administrator-role system.
That setting also controls Devise's sender. Application mailers separately use
the sender in `app/mailers/application_mailer.rb`.

Development uses Rails' asynchronous in-process adapter and sends SMTP mail to
Mailpit. Inspect messages at http://localhost:8025. Restarting Rails can discard
pending development jobs; this is not a persistent production queue. The UI's
sent/resent messages acknowledge the action, not guaranteed inbox delivery.

Production uses persistent Solid Queue and needs a running worker, either as a
separate process:

```sh
RAILS_ENV=production bin/jobs
```

or using Puma's existing supervisor integration with `SOLID_QUEUE_IN_PUMA=1`.
Use one of these approaches for a simple deployment. `config/queue.yml` consumes
`"*"`, including all queues listed above. Failed production jobs can be inspected
and retried through the queue backend.

## Tests

Start the development services and prepare the separate test database:

```sh
docker compose exec web bundle exec rails db:prepare RAILS_ENV=test
```

Run model, request, job, mailer, and integration tests without a browser:

```sh
docker compose exec web bundle exec rails test
```

Start Firefox/Selenium when needed, then run system tests:

```sh
docker compose --profile system-test up -d selenium
docker compose exec web bundle exec rails test:system
```

Run the complete suite, or a specific file:

```sh
docker compose exec web bundle exec rails test:all
docker compose exec web bundle exec rails test test/system/invitation_acceptances_test.rb
```

System tests serve Capybara on `web:3001` for the remote Firefox container. They
run sequentially because that port is shared. Non-system tests run in parallel
above Rails' configured threshold when invoked separately with `rails test`;
`test:all` runs sequentially. Do not run separate test commands concurrently
against the same test databases.

```sh
docker compose exec web bundle exec rubocop
docker compose logs -f selenium
```

## Before the family beta

Deployment/hosting is still to be decided. The development Compose file is not
a complete production deployment configuration. Before deploying:

- Prepare the primary, cache, queue, and cable databases.
- Configure production SMTP, an appropriate ApplicationMailer sender,
  `DEVISE_MAILER_SENDER`, and Action Mailer's real host/protocol. The current
  production URL host and application sender are placeholders. The production
  configuration assumes HTTPS behind a TLS-terminating proxy.
- Supply the deployment's Rails credentials/secrets, keeping the signing secret
  stable across restarts so outstanding invitation links remain valid.
- Verify actual delivery from a live Solid Queue worker.

Finish the manual two-browser/Mailpit walkthrough in [TODO.md](TODO.md): invite a
new account and an existing account, check both email variants, accept each
explicitly, verify independent invitations and cancelled links, and confirm
friendship removal revokes list access. Automated browser/mail tests pass, but
these manual acceptance checks remain open.
