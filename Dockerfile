#FROM instructure/tini:latest as tini

ARG RUBY=3.1

FROM instructure/ruby-passenger:3.1

# LABEL about the custom image
LABEL maintainer="mchristopher"
LABEL version="0.1"
LABEL description="This is custom Docker Image for Canvas LMS."

ARG POSTGRES_CLIENT=14
ENV APP_HOME /usr/src/app/
ENV RAILS_ENV production
ENV NGINX_MAX_UPLOAD_SIZE 10g
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_CTYPE en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV DEBIAN_FRONTEND=noninteractive
ENV CANVAS_BUILD_CONCURRENCY 1
ARG CANVAS_RAILS=7.0
ENV CANVAS_RAILS=${CANVAS_RAILS}

ARG JS_BUILD_NO_UGLIFY=0
ARG RAILS_LOAD_ALL_LOCALES=0
ARG CRYSTALBALL_MAP=0

ENV NODE_MAJOR 18
ENV YARN_VERSION 1.19.1-1
#ENV BUNDLER_VERSION 2.3.26
ENV GEM_HOME /home/docker/.gem/$RUBY
ENV PATH ${APP_HOME}bin:$GEM_HOME/bin:$PATH
ENV BUNDLE_APP_CONFIG /home/docker/.bundle

WORKDIR $APP_HOME

USER root

ARG USER_ID
# This step allows docker to write files to a host-mounted volume with the correct user permissions.
# Without it, some linux distributions are unable to write at all to the host mounted volume.
RUN if [ -n "$USER_ID" ]; then usermod -u "${USER_ID}" docker \
        && chown --from=9999 docker /usr/src/nginx /usr/src/app -R; fi

RUN mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
  && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
  && echo "deb https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list \
  && printf 'path-exclude /usr/share/doc/*\npath-exclude /usr/share/man/*' > /etc/dpkg/dpkg.cfg.d/01_nodoc \
  && echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
  && curl -sS https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
  && add-apt-repository ppa:git-core/ppa -ny \
  && apt-get update -qq \
  && apt-get install -qqy --no-install-recommends \
       nodejs \
       less \
       yarn="$YARN_VERSION" \
       libxmlsec1-dev \
       python3-lxml \
       python-is-python3 \
       libicu-dev \
       libidn11-dev \
       parallel \
       postgresql-client-$POSTGRES_CLIENT \
       unzip \
       pbzip2 \
       vim \
       fontforge \
       git \
       build-essential \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /home/docker/.gem/ruby/$RUBY_MAJOR.0

RUN gem install bundler --no-document -v 2.5.7 \
  && find $GEM_HOME ! -user docker | xargs chown docker:docker
RUN npm install -g npm@9.8.1 && npm cache clean --force

# Switch to docker user to install app
RUN mkdir -p /usr/src/app && chown -R docker /usr/src/app

USER docker

# Download Canvas and install
RUN cd /usr/src/app/ \
    && git clone --depth=1 --branch prod https://github.com/instructure/canvas-lms.git . \
    && rm -fr .git

# Copy the sample config files
RUN for config in delayed_jobs external_migration; \
    do cp config/$config.yml.example config/$config.yml; done

COPY ./config/amazon_s3.yml /usr/src/app/config/amazon_s3.yml
COPY ./config/cache_store.yml /usr/src/app/config/cache_store.yml
COPY ./config/database.yml /usr/src/app/config/database.yml
COPY ./config/domain.yml /usr/src/app/config/domain.yml
COPY ./config/file_store.yml /usr/src/app/config/file_store.yml
COPY ./config/redis.yml /usr/src/app/config/redis.yml
COPY ./config/security.yml /usr/src/app/config/security.yml
COPY ./config/outgoing_mail.yml /usr/src/app/config/outgoing_mail.yml
COPY ./config/dynamic_settings.yml /usr/src/app/config/dynamic_settings.yml

RUN set -eux; \
  mkdir -p \
    .yardoc \
    app/stylesheets/brandable_css_brands \
    app/views/info \
    config/locales/generated \
    log \
    node_modules \
    packages/js-utils/es \
    packages/js-utils/lib \
    packages/js-utils/node_modules \
    pacts \
    public/dist \
    public/doc/api \
    public/javascripts/translations \
    reports \
    tmp \
    /home/docker/.bundle/ \
    /home/docker/.cache/yarn \
    /home/docker/.gem/

RUN set -eux; \
  bundle install \
  && yarn install \
  && yarn gulp rev

RUN touch app/stylesheets/_brandable_variables_defaults_autogenerated.scss \
    && touch log/production.log \
    && COMPILE_ASSETS_API_DOCS=0 \
       COMPILE_ASSETS_BRAND_CONFIGS=0 \
       bundle exec rails canvas:compile_assets

USER root

# Expose HTTP port
EXPOSE 80
ENV CG_HTTPS_PORT 80
ENV CG_HTTP_PORT 80
ENV CG_ENVIRONMENT local

USER docker
