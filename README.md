# Wishlist

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## Running Tests

Ensure Selenium container is started:

    $ docker-compose --profile system-test up -d selenium

Run the tests (excluding system tests):

    $ docker compose exec web bundle exec rails test

Run the tests (including sytem tests):

    $ docker compose exec web bundle exec rails test:all

To watch the Selenium logs:

    $ docker compose logs -f selenium

## Background email notifications

Friendship request and acceptance emails are delivered by dedicated Active Job
jobs on the `friendship_notification` queue. Controllers enqueue after the
transaction commits; they never send email themselves. Jobs skip requests that
have already been resolved and friendships that have been removed.

Development uses Rails' asynchronous in-process job adapter and sends SMTP mail
to Mailpit. Inspect messages at http://localhost:8025. Restarting the development
process can discard pending async jobs; production uses persistent Solid Queue.

Production must run a Solid Queue worker, either as a separate process:

```sh
RAILS_ENV=production bin/jobs
```

or through the existing Puma supervisor integration with
`SOLID_QUEUE_IN_PUMA=1`. The existing `config/queue.yml` worker consumes `"*"`,
which includes `friendship_notification` and the existing registration queues.
Prepare the production databases and configure SMTP, the ApplicationMailer sender,
and Action Mailer's URL host/protocol before deployment. Verify delivery from the
live worker during hosting setup. Delivery failures are handled outside the web
request and do not undo a saved friendship; failed jobs can be inspected/retried
through the queue backend.
