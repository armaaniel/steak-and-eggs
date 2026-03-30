FROM ruby:3.4.9-slim-bookworm
WORKDIR /app

RUN apt-get update && apt-get install -y git build-essential libpq-dev libyaml-dev

COPY Gemfile Gemfile.lock ./
ENV BUNDLE_WITHOUT="development:test"
ENV RAILS_ENV=production
RUN bundle install

COPY . .

ENTRYPOINT ["./bin/docker-entrypoint"]
CMD ["./bin/rails", "server"]

