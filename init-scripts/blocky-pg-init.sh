#!/bin/bash
# Copyright (C) 2023-2024 Shizun Ge
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#

set -e

# Create a reader user and grant select capability.
# Read the password from a file.
READER_PASSWORD=$(head -1 ${READER_PASSWORD_FILE})
psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" <<-EOSQL
  CREATE USER ${READER_USERNAME} WITH PASSWORD '${READER_PASSWORD}';
  GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO ${READER_USERNAME};
  GRANT USAGE ON SCHEMA public to ${READER_USERNAME};
  GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${READER_USERNAME};
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ${READER_USERNAME};
EOSQL

HBA=/var/lib/postgresql/data/pg_hba.conf
# Remove the default access control.
sed -i "s/^host[[:space:]]\+all[[:space:]]\+all[[:space:]]\+all/# host all all all/g" ${HBA}
# Each row: connection database user address auth-method
# Do not allow connections for the POSTGRES_USER from the reverse proxy i.e. from the internet.
for REVERSE_PROXY in ${REVERSE_PROXIES}; do
  echo "host all ${POSTGRES_USER} ${REVERSE_PROXY} reject" >> ${HBA}
  # The reverse proxy should be also within the private network. Thus this may be redundant.
  echo "host all ${READER_USERNAME} ${REVERSE_PROXY} scram-sha-256" >> ${HBA}
done
# Allow connections from private networks.
echo "host all all 10.0.0.0/8 scram-sha-256" >> ${HBA}
echo "host all all 172.16.0.0/12 scram-sha-256" >> ${HBA}
echo "host all all 192.168.0.0/16 scram-sha-256" >> ${HBA}
cat ${HBA}

