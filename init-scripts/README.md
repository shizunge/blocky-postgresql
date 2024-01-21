## blocky postgresql initialization script

This is an initialization script for [Docker offical postgresql image](https://hub.docker.com/_/postgres) to avoid malicious SQL statements and unauthorized access.

### Features

#### Create a reader user

This script creates a reader user and grand only select permissions to avoid malicious SQL statements. It addresses the issue of the following warning you received when you added a Postgresql data source to Grafana.

> WARNING: The database user should only be granted SELECT permissions on the specified database & tables you want to query. 
> Grafana does not validate that queries are safe so queries can contain any SQL statement. For example, statements like DELETE FROM user; and DROP TABLE user; would be executed.
> To protect against this we Highly recommend you create a specific PostgreSQL user with restricted permissions. Check out the docs for more information.

Use environment variable `READER_USERNAME` to specify the user name for the reader.

Use environment variable `READER_PASSWORD_FILE` to specify where to read the password. The script reads the password from a file, thus it works with [docker secrets](https://docs.docker.com/engine/swarm/secrets/).

The script also uses environment variables `POSTGRES_USER` and `POSTGRES_DB` available on the Docker offical postgresql image. It assumes the *blocky* database is `POSTGRES_DB`.

Here is the code snippet.
```
# Create a reader user and grant select permissions.
# Read the password from a file.
READER_PASSWORD=$(head -1 ${READER_PASSWORD_FILE})
psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" <<-EOSQL
  CREATE USER ${READER_USERNAME} WITH PASSWORD '${READER_PASSWORD}';
  GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO ${READER_USERNAME};
  GRANT USAGE ON SCHEMA public to ${READER_USERNAME};
  GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${READER_USERNAME};
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ${READER_USERNAME};
EOSQL
```

#### Restraint access, allow only ipv4 private networks

You can use the database initialization script to restraint who can access from where.

You want to allow `POSTGRES_USER`, which is probably used by *blocky* and has full permissions, to access the database only from *blocky*, which may be within the same private network.

The script reads the environment variable `REVERSE_PROXIES`, then rejects accesses of `POSTGRES_USER` from the reverse proxies, only allows `READER_USERNAME` to access from the reverse proxies i.e. from the internet.

`REVERSE_PROXIES` can contains IP addresses or host names. The *address* section of the [`pg_hba.conf` document](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html) adescribes how host names work.

Here is the code snippet.
```
HBA=/var/lib/postgresql/data/pg_hba.conf
# Remove the default access control.
sed -i "s/^host[[:space:]]\+all[[:space:]]\+all[[:space:]]\+all/# host all all all/g" ${HBA}
# Each row: connection database user address auth-method
# Do not allow connections for the POSTGRES_USER from the reverse procy i.e. from the internet.
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
```

### Caveats

1. Data directory must be empty

    As mentioned in the [document](https://github.com/docker-library/docs/blob/master/postgres/README.md#initialization-scripts) of the Postgresql image, the scripts are only run if you start the container with a data directory that is empty.

1. Script must be readable by UID 999

    The `postgres` inside the container does not care the UID, but the `initdb` does care.
    The script must be readable by UID 999, which is the UID used by `initdb` inside the container.
    See [Arbitrary `--user` Notes](https://github.com/docker-library/docs/blob/master/postgres/README.md#arbitrary---user-notes).

