FROM quay.io/fundingcircle/alpine-ruby:2.3 as builder

RUN apk --no-cache add linux-headers postgresql-dev build-base cmake libgit2-dev 
WORKDIR /tmp
COPY .ruby-version /tmp/
COPY Gemfile* /tmp/
RUN bundle config build.libv8 --with-system-v8 && \
  bundle install --binstubs --deployment --jobs=4 --retry=3 --without development test

FROM quay.io/fundingcircle/alpine-ruby:2.3
LABEL maintainer="Funding Circle Engineering <engineering+ST@fundingcircle.com>"

RUN apk --no-cache add linux-headers build-base cmake libgit2-dev zlib-dev linux-headers postgresql-dev && \
  addgroup -g 1101 shipment_tracker && \
  adduser -S -u 1101 -h /app -G shipment_tracker shipment_tracker
USER shipment_tracker
WORKDIR /app
COPY --from=builder --chown=shipment_tracker:shipment_tracker /tmp .
COPY --chown=shipment_tracker:shipment_tracker . .
COPY --chown=shipment_tracker:shipment_tracker docker/dropzone.yaml /usr/local/deploy/dropzone.yaml 

ENTRYPOINT ["/app/docker/entrypoint.sh"]
