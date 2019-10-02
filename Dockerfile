FROM ruby:2.6.3-alpine3.9

EXPOSE 1812/udp 1813/udp 3000

RUN apk --no-cache add \
      wpa_supplicant freeradius freeradius-rest freeradius-eap openssl \
      make gcc libc-dev python3 && \
      pip3 install awscli

# Set up the radius configs

RUN mkdir /tmp/radiusd
RUN rm -rf /etc/raddb && mkdir -p /etc/raddb
COPY radius /etc/raddb
RUN openssl dhparam -out /etc/raddb/certs/dh 1024

# Set up the healtcheck service

ARG BUNDLE_ARGS="--deployment --no-cache --no-prune --jobs=8 --without test"

WORKDIR /usr/src/healthcheck
COPY healthcheck/Gemfile* healthcheck/.ruby-version ./
RUN bundle install $BUNDLE_ARGS
COPY healthcheck ./

# these were needed while bundling, but no longer
RUN apk del make gcc libc-dev

# ensure we're in the correct workdir at the end
WORKDIR /usr/src/healthcheck

# set up envs we need
## healtcheck
ENV HEALTH_CHECK_IDENTITY ""
ENV HEALTH_CHECK_PASSWORD ""
ENV HEALTH_CHECK_RADIUS_KEY ""
ENV HEALTH_CHECK_SSID ""

## radius fetched files
ENV CERT_STORE_BUCKET ""
ENV WHITELIST_BUCKET ""
ENV ENDPOINT_URL ""

## radius envs
ENV AUTHORISATION_API_BASE_URL ""
ENV LOGGING_API_BASE_URL ""
ENV RADIUSD_PARAMS ""

CMD [ "/bin/sh", "-c", \
      "ENDPOINT_ARG=${ENDPOINT_URL:+--endpoint-url=$ENDPOINT_URL}; \
      aws ${ENDPOINT_ARG} s3 cp ${WHITELIST_BUCKET}/clients.conf /etc/raddb/clients.conf; \
      aws ${ENDPOINT_ARG} s3 cp ${CERT_STORE_BUCKET}/ca.pem /etc/raddb/certs/ca.pem; \
      aws ${ENDPOINT_ARG} s3 cp ${CERT_STORE_BUCKET}/comodoCA.pem /etc/raddb/certs/comodoCA.pem; \
      aws ${ENDPOINT_ARG} s3 cp ${CERT_STORE_BUCKET}/server.key /etc/raddb/certs/server.key; \
      aws ${ENDPOINT_ARG} s3 cp ${CERT_STORE_BUCKET}/server.pem /etc/raddb/certs/server.pem; \
      bundle exec rackup -o 0.0.0.0 -p 3000 & /usr/sbin/radiusd $RADIUSD_PARAMS | cat" \
      ]
