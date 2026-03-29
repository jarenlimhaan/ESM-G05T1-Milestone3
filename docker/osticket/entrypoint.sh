#!/bin/sh
set -eu

CONFIG_FILE="/var/www/html/include/ost-config.php"

if [ -f "$CONFIG_FILE" ] && grep -q "%CONFIG-DBHOST" "$CONFIG_FILE"; then
  DBHOST="${MYSQL_HOST:-osticket-db}"
  DBNAME="${MYSQL_DATABASE:-osticket}"
  DBUSER="${MYSQL_USER:-osticket}"
  DBPASS="${MYSQL_PASSWORD:-osticket}"
  DBPREFIX="${OSTICKET_DB_PREFIX:-ost_}"
  ADMIN_EMAIL_VALUE="${ADMIN_EMAIL:-${INSTALL_EMAIL:-admin@example.com}}"
  SECRET_SALT_VALUE="$(head -c 48 /dev/urandom | base64 | tr -d '\n' | cut -c1-48)"

  sed -i "s|define('OSTINSTALLED',FALSE);|define('OSTINSTALLED',TRUE);|g" "$CONFIG_FILE"
  sed -i "s|%CONFIG-DBHOST|${DBHOST}|g" "$CONFIG_FILE"
  sed -i "s|%CONFIG-DBNAME|${DBNAME}|g" "$CONFIG_FILE"
  sed -i "s|%CONFIG-DBUSER|${DBUSER}|g" "$CONFIG_FILE"
  sed -i "s|%CONFIG-DBPASS|${DBPASS}|g" "$CONFIG_FILE"
  sed -i "s|%CONFIG-PREFIX|${DBPREFIX}|g" "$CONFIG_FILE"
  sed -i "s|%ADMIN-EMAIL|${ADMIN_EMAIL_VALUE}|g" "$CONFIG_FILE"
  sed -i "s|%CONFIG-SIRI|${SECRET_SALT_VALUE}|g" "$CONFIG_FILE"

  chmod 0640 "$CONFIG_FILE"
  chown www-data:www-data "$CONFIG_FILE"
fi

exec apache2-foreground
