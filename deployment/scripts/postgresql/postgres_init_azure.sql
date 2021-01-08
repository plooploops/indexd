/* Entrypoint script for postgres container to set up databases and users for 
docker-compose setup */

/* This should run under the postgres user context (or the server admin)
   psql -v ssmlmode=true -U postgres@mypostgresserver123 -h mypostgresserver123.postgres.database.azure.com -p 5432 -W postgres
*/

CREATE DATABASE metadata_db;
CREATE DATABASE fence_db;
CREATE DATABASE indexd_db;
CREATE DATABASE arborist_db;

CREATE USER fence_user;
ALTER USER fence_user WITH PASSWORD 'fence_pass';
GRANT azure_pg_admin to fence_user;

CREATE USER peregrine_user;
ALTER USER peregrine_user WITH PASSWORD 'peregrine_pass';
GRANT azure_pg_admin to peregrine_user;

CREATE USER sheepdog_user;
ALTER USER sheepdog_user WITH PASSWORD 'sheepdog_pass';
GRANT azure_pg_admin to sheepdog_user;

CREATE USER indexd_user;
ALTER USER indexd_user WITH PASSWORD 'indexd_pass';
GRANT azure_pg_admin to indexd_user;

CREATE USER arborist_user;
ALTER USER arborist_user WITH PASSWORD 'arborist_pass';
GRANT azure_pg_admin to arborist_user;

