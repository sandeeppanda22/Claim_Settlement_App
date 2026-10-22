-- =====================================================================
-- role.sql — one-time creation of the claim_app application role and the
-- claim_settlement_dev database. Must be run by a superuser (postgres),
-- since claim_app itself cannot CREATE ROLE or CREATE DATABASE.
--
-- build.sh's Phase 0 is the only supported way to run this: it prompts
-- for the claim_app password interactively and passes it in as a psql
-- variable, so this file never needs hand-editing. It requires that
-- variable — do NOT run this file directly with plain `psql -f`; use:
--
--   psql -U postgres -v claim_app_password='your-chosen-password' -f database/role.sql
--
-- Idempotent: safe to rerun. Roles and databases are cluster-level and
-- are not touched by build.sh's per-table existence gating (that gating
-- only applies to the schema objects created by database/ddl/*.sql).
--
-- claim_app is deliberately plain LOGIN — no SUPERUSER, no BYPASSRLS.
-- Every tenant table has FORCE ROW LEVEL SECURITY (08_rls_policies.sql),
-- so claim_app can safely own every schema object: ownership never
-- bypasses RLS, only SUPERUSER/BYPASSRLS do.
-- =====================================================================

-- CREATE ROLE can't be parameterized inside a DO $$...$$ block either —
-- psql's client-side :'var' substitution does not fire inside dollar-
-- quoted bodies, so the password would reach the server as a literal,
-- unsubstituted ":'claim_app_password'" token and fail to parse. Guarded
-- the same way as CREATE DATABASE below: build the statement text with
-- format(%L) (safe quoting) and run it via \gexec.
SELECT format('CREATE ROLE claim_app WITH LOGIN PASSWORD %L NOSUPERUSER NOBYPASSRLS', :'claim_app_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'claim_app')
\gexec

-- CREATE DATABASE cannot run inside DO/a transaction block — guarded with
-- a psql-side check via \gexec instead of a plain CREATE DATABASE, so
-- rerunning this file never errors with "database already exists".
SELECT 'CREATE DATABASE claim_settlement_dev OWNER claim_app'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'claim_settlement_dev')
\gexec

GRANT ALL PRIVILEGES ON DATABASE claim_settlement_dev TO claim_app;
