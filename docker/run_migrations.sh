#!/bin/sh -e
/app/docker/entrypoint.sh /usr/bin/bundle exec rake --trace db:migrate
