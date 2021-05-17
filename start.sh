rm -f /var/run/apache2/apache2.pid
/etc/init.d/canvas_init start &
source /etc/apache2/envvars
/usr/sbin/apache2ctl -D FOREGROUND -e info
