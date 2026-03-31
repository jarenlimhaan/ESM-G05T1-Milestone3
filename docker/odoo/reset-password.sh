#!/bin/bash
# Reset odoo17 user password to match .env
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    ALTER USER odoo17 WITH PASSWORD '$POSTGRES_PASSWORD';
EOSQL
