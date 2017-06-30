FROM ruby:2.4-alpine

ADD Gemfile /app/
ADD Gemfile.lock /app/

WORKDIR /app

RUN apk --update add --virtual build-dependencies ruby-dev build-base && \
    gem install bundler --no-ri --no-rdoc && \
    cd /app ; bundle install --without development test && \
    apk del build-dependencies

COPY . /app/

CMD bundle exec puma -p 9393 -e production
