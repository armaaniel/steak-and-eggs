FROM ruby:3.4.9-slim-bookworm
WORKDIR /app

RUN apt-get update && apt-get install -y git build-essential libpq-dev libyaml-dev libjemalloc2 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so

ENV LD_PRELOAD="/usr/local/lib/libjemalloc.so"
RUN MALLOC_CONF=stats_print:true ruby -e "" 2>&1 | grep -q "jemalloc statistics"

COPY Gemfile Gemfile.lock ./
ENV BUNDLE_WITHOUT="development:test"
ENV RAILS_ENV=production
RUN bundle install

COPY . .

ENTRYPOINT ["./bin/docker-entrypoint"]
CMD ["./bin/rails", "server"]