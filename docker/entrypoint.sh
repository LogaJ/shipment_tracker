#!/bin/sh -e
/usr/bin/envconsul-launch -prefix shipment_tracker/config \
                          "$@"
