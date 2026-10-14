#!/bin/bash
# App bootstrap. Runs on first boot with full root privileges —
# and with the database password baked into it.
echo "starting photo-share..."
PGPASSWORD="${db_password}" psql -h db.internal -U app -c "SELECT 1"
echo "db password in use: ${db_password}" >> /var/log/bootstrap.log
