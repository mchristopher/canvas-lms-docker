#!/bin/bash
set -e

rm -f /var/run/apache2/apache2.pid
source /etc/apache2/envvars
/usr/sbin/apache2ctl -D FOREGROUND -e info
