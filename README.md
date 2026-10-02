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

Run the tests:

    $ docker compose exec web bundle exec rails test

To watch the Selenium logs:

    $ docker compose logs -f selenium
