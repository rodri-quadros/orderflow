#!/bin/sh
# Cria o usuário da aplicação com privilégio mínimo (somente DML, sem DDL).
# Executado pelo entrypoint do PostgreSQL como admin, apenas na primeira
# inicialização (volume vazio). Para reexecutar: docker compose down -v
set -e

: "${APP_DB_USER:?APP_DB_USER não definido}"
: "${APP_DB_PASSWORD:?APP_DB_PASSWORD não definido}"

psql -v ON_ERROR_STOP=1 \
     --username "$POSTGRES_USER" \
     --dbname "$POSTGRES_DB" \
     -v usuario="$APP_DB_USER" \
     -v senha="$APP_DB_PASSWORD" \
     -v banco="$POSTGRES_DB" <<'EOSQL'
CREATE ROLE :"usuario" LOGIN PASSWORD :'senha';

-- No PostgreSQL 15+ o schema public já não concede CREATE a PUBLIC;
-- o REVOKE explícito deixa a intenção clara.
REVOKE ALL ON DATABASE :"banco" FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

GRANT CONNECT ON DATABASE :"banco" TO :"usuario";
GRANT USAGE ON SCHEMA public TO :"usuario";

-- Vale para as tabelas e sequências criadas depois pelo admin (02_schema.sql).
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"usuario";
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO :"usuario";
EOSQL
