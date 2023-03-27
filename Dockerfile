FROM instructure/tini:latest as tini

ARG RUBY=2.7

FROM instructure/ruby-passenger:2.7

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

ENV YARN_VERSION 1.19.1-1
ENV BUNDLER_VERSION 2.3.26
ENV GEM_HOME /home/docker/.gem/$RUBY
ENV PATH $GEM_HOME/bin:$PATH
ENV BUNDLE_APP_CONFIG /home/docker/.bundle

WORKDIR $APP_HOME

USER root

ARG USER_ID
# This step allows docker to write files to a host-mounted volume with the correct user permissions.
# Without it, some linux distributions are unable to write at all to the host mounted volume.
RUN if [ -n "$USER_ID" ]; then usermod -u "${USER_ID}" docker \
        && chown --from=9999 docker /usr/src/nginx /usr/src/app -R; fi

RUN curl -sL https://deb.nodesource.com/setup_16.x | bash - \
  && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
  && echo "deb https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list \
  && printf 'path-exclude /usr/share/doc/*\npath-exclude /usr/share/man/*' > /etc/dpkg/dpkg.cfg.d/01_nodoc \
  && echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
  && curl -sS https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
  && apt-get update -qq \
  && apt-get install -qqy --no-install-recommends \
       nodejs \
       yarn="$YARN_VERSION" \
       libxmlsec1-dev \
       python3-lxml \
       libicu-dev \
       libidn11-dev \
       parallel \
       postgresql-client-$POSTGRES_CLIENT \
       unzip \
       pbzip2 \
       fontforge \
       git \
       build-essential \
       python-is-python3 \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /home/docker/.gem/ruby/$RUBY_MAJOR.0

RUN if [ -e /var/lib/gems/$RUBY_MAJOR.0/gems/bundler-* ]; then BUNDLER_INSTALL="-i /var/lib/gems/$RUBY_MAJOR.0"; fi \
  && gem uninstall --all --ignore-dependencies --force $BUNDLER_INSTALL bundler \
  && gem install bundler --no-document -v $BUNDLER_VERSION \
  && find $GEM_HOME ! -user docker | xargs chown docker:docker
RUN npm install -g npm@latest && npm cache clean --force

# Switch to docker user to install app
RUN mkdir -p /usr/src/app && chown -R docker /usr/src/app

USER docker

# Download Canvas and install
RUN cd /usr/src/app/ \
    && git clone --depth=1 --branch prod https://github.com/instructure/canvas-lms.git . \
    && rm -fr .git

# Copy the sample config files
RUN for config in delayed_jobs outgoing_mail external_migration; \
    do cp config/$config.yml.example config/$config.yml; done

COPY ./config/amazon_s3.yml /usr/src/app/config/amazon_s3.yml
COPY ./config/cache_store.yml /usr/src/app/config/cache_store.yml
COPY ./config/database.yml /usr/src/app/config/database.yml
COPY ./config/domain.yml /usr/src/app/config/domain.yml
COPY ./config/file_store.yml /usr/src/app/config/file_store.yml
COPY ./config/redis.yml /usr/src/app/config/redis.yml
COPY ./config/security.yml /usr/src/app/config/security.yml
COPY ./config/outgoing_mail.yml /usr/src/app/config/outgoing_mail.yml

RUN set -eux; \
  mkdir -p \
    .yardoc \
    app/stylesheets/brandable_css_brands \
    app/views/info \
    config/locales/generated \
    gems/canvas_i18nliner/node_modules \
    log \
    node_modules \
    packages/canvas-media/es \
    packages/canvas-media/lib \
    packages/canvas-media/node_modules \
    packages/canvas-planner/lib \
    packages/canvas-planner/node_modules \
    packages/canvas-rce/canvas \
    packages/canvas-rce/lib \
    packages/canvas-rce/node_modules \
    packages/jest-moxios-utils/node_modules \
    packages/js-utils/es \
    packages/js-utils/lib \
    packages/js-utils/node_modules \
    packages/k5uploader/es \
    packages/k5uploader/lib \
    packages/k5uploader/node_modules \
    packages/old-copy-of-react-14-that-is-just-here-so-if-analytics-is-checked-out-it-doesnt-change-yarn.lock/node_modules \
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
  \
  # set up bundle config options \
  bundle config --global build.nokogiri --use-system-libraries \
  && bundle config --global build.ffi --enable-system-libffi \
  && mkdir -p \
    /home/docker/.bundle \
  # TODO: --without development \
  && bundle install --jobs $(nproc) \
  && rm -rf $GEM_HOME/cache \
  && rm -rf $GEM_HOME/bundler/gems/*/{.git,spec,test,features} \
  && rm -rf $GEM_HOME/gems/*/{spec,test,features} \
  && (DISABLE_POSTINSTALL=1 yarn install --pure-lockfile || DISABLE_POSTINSTALL=1 yarn install --pure-lockfile --network-concurrency 1) \
  && yarn cache clean \
  && ./script/fix_inst_esm.js \
  && yarn build:packages

#RUN bash -c "if [[ "$RAILS_LOAD_ALL_LOCALES" == "0" ]]; then cp -v public/javascripts/translations/_core_en.js public/javascripts/translations/en.js; fi"
RUN COMPILE_ASSETS_API_DOCS=0 \
    COMPILE_ASSETS_BRAND_CONFIGS=0 \
    COMPILE_ASSETS_NPM_INSTALL=0 \
    COMPILE_ASSETS_STYLEGUIDE=0 \
    JS_BUILD_NO_UGLIFY="$JS_BUILD_NO_UGLIFY" \
    RAILS_LOAD_ALL_LOCALES="$RAILS_LOAD_ALL_LOCALES" \
    CRYSTALBALL_MAP="$CRYSTALBALL_MAP" \
    bundle exec rails canvas:compile_assets

# RUN bundle install --without test development \
#     && bundle clean --force \
#     && chown -R canvasuser public/dist/brandable_css \
#     && unlink /etc/apache2/sites-enabled/000-default.conf \
#     && chown canvasuser config/*.yml \
#     && chmod 400 config/*.yml

# Finish image setup
USER root

# RUN ln -s /usr/src/app/script/canvas_init /etc/init.d/canvas_init
# RUN update-rc.d canvas_init defaults

# RUN rm -rf \
#     /root/.bundle/cache \
#     /var/lib/gems/2.7.0/cache \
#     /var/lib/gems/2.7.0/bundler/gems/*/{.git,spec,test,features} \
#     /var/lib/gems/2.7.0/gems/*/{spec,test,features} \
#     /root/.gem/cache \
#     /root/.gem/bundler/gems/*/{.git,spec,test,features} \
#     /root/.gem/gems/*/{spec,test,features} \
#     `yarn cache dir` \
#     /root/.node-gyp \
#     /tmp/phantomjs \
#     .yardoc \
#     config/locales/generated \
#     gems/*/node_modules \
#     gems/plugins/*/node_modules \
#     log \
#     public/dist/maps \
#     public/doc/api/*.json \
#     public/javascripts/translations \
#     tmp-*.tmp \
#   && mkdir -p log \
#   && touch log/production.log

# # Make logs writable
# RUN rm -fr log \
#   && mkdir -p log \
#   && chmod 777 log

# Expose HTTP port
EXPOSE 80
ENV CG_HTTPS_PORT 80
ENV CG_HTTP_PORT 80
ENV CG_ENVIRONMENT local

#COPY ./config/canvas_no_ssl.conf /etc/apache2/sites-enabled/canvas.conf
#COPY ./start.sh /var/canvas/start.sh
#RUN chmod +x /var/canvas/start.sh

USER docker
#ENTRYPOINT ["/tini", "--"]
#CMD ["/var/canvas/start.sh"]
