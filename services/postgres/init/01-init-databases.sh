#!/bin/sh
set -e

database_password="${POSTGRES_DATABASE_PASSWORD:-changeme}"

if [ -z "${POSTGRES_DATABASES:-}" ]; then
  echo "No additional POSTGRES_DATABASES requested."
  exit 0
fi

for database_name in $POSTGRES_DATABASES; do
  case "$database_name" in
    *[!A-Za-z0-9_]* | [0-9]* | "")
      echo "Invalid database name '$database_name'. Use letters, numbers, and underscores; do not start with a number." >&2
      exit 1
      ;;
  esac

  role_exists="$(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --tuples-only --no-align --command "SELECT 1 FROM pg_roles WHERE rolname = '$database_name';")"
  if [ "$role_exists" != "1" ]; then
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --command "CREATE USER \"$database_name\" WITH PASSWORD '$database_password';"
    echo "Created PostgreSQL user '$database_name'."
  else
    echo "PostgreSQL user '$database_name' already exists."
  fi

  database_exists="$(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --tuples-only --no-align --command "SELECT 1 FROM pg_database WHERE datname = '$database_name';")"
  if [ "$database_exists" != "1" ]; then
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --command "CREATE DATABASE \"$database_name\" OWNER \"$database_name\";"
    echo "Created PostgreSQL database '$database_name'."
  else
    echo "PostgreSQL database '$database_name' already exists."
  fi

  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --command "GRANT ALL PRIVILEGES ON DATABASE \"$database_name\" TO \"$database_name\";"
done
