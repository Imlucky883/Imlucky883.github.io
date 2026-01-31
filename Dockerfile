
# ---------- build stage ----------
FROM ruby:3.2-alpine AS builder

# Only what is required to build gems
RUN apk add --no-cache \
    build-base \
    git \
    nodejs

WORKDIR /srv/jekyll

COPY Gemfile Gemfile.lock ./

# Install bundler matching lockfile major version
RUN gem install bundler -v 4.0.4 \
 && bundle install --without development test

COPY . .

RUN bundle exec jekyll build

# ---------- runtime stage ----------
FROM ruby:3.2-alpine

WORKDIR /srv/jekyll

# Copy only the built site
COPY --from=builder /srv/jekyll/_site ./_site

# Minimal runtime command
EXPOSE 4000
CMD ["ruby", "-run", "-ehttpd", "_site", "-p4000"]
