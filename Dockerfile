# syntax=docker/dockerfile:1
# check=error=true

ARG RUBY_VERSION=4.0.6
FROM docker.io/library/ruby:$RUBY_VERSION-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y \
      build-essential \
      git \
      libpq-dev \
      libvips \
      postgresql-client \
      pkg-config && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./

RUN bundle install

COPY . .

CMD ["bin/dev"]
