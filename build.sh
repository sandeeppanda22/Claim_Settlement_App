#!/usr/bin/env bash
# =====================================================================
# build.sh — builds the Claim Settlement App schema from database/ddl/,
# styled after NSS ERP's database/scripts/02_build.sh: decomposed
# connection params, interactive password prompt, colorized phase
# output, and idempotent skip-on-already-applied instead of a hard
# drop-and-recreate.
#
# Prerequisite: the claim_app role and claim_settlement_dev database must
# exist. Phase 0 below checks for claim_app and, if missing, prompts for
# both the postgres superuser's password and the claim_app password to
# create it with, then runs database/role.sql automatically — no separate
# manual step, and no password ever hardcoded in role.sql.
#
# Usage (run from the project root): ./build.sh [db_name] [db_user] [db_host] [db_port]
#   e.g. ./build.sh
#        ./build.sh claim_settlement_dev claim_app localhost 5432
#
# Granularity note: each file under database/ddl/ creates several
# tables together (e.g. 01_tenancy.sql creates company,
# company_email_domain, role, and company_user as one unit — see
# CLAUDE.md, "DDL-only schema changes"). So existence-gating here is
# per FILE, checked against that file's first table — not per-table
# like NSS ERP, whose DDL happens to be one table per file. A file is
# skipped once its first table exists; it is never re-applied.
#
# Consequence (same caveat NSS ERP documents for itself): editing a
# column or constraint on an EXISTING table inside one of these DDL
# files has no effect on a normal rerun. To pick up such a change, do
# a manual hard rebuild first:
#   psql -U claim_app -d claim_settlement_dev -c \
#     "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
#   then rerun this script.
# =====================================================================
set -euo pipefail

# ---------------------------------------------------------------------
# Phase 0 — connection parameters
# ---------------------------------------------------------------------
DB_NAME="${1:-claim_settlement_dev}"
DB_USER="${2:-claim_app}"
DB_HOST="${3:-localhost}"
DB_PORT="${4:-5432}"

# This script now lives at the project root, so everything it needs is
# addressed relative to that root rather than to database/.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DDL_DIR="${SCRIPT_DIR}/database/ddl"
REQUIREMENTS_FILE="${SCRIPT_DIR}/api/requirements.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---------------------------------------------------------------------
# Phase 0a — ensure the claim_app role / claim_settlement_dev database
# exist, by running role.sql as the postgres superuser if claim_app
# isn't there yet. Uses a throwaway PGPASSWORD scoped to this one check
# (unset afterward) so it never leaks into the claim_app connection used
# by every phase below.
#
# The claim_app password itself is always prompted for here (not just
# when the role is missing) because every phase after this one connects
# as claim_app — asking once up front means role.sql, if it runs, gets
# that same password passed in as a psql variable (no hardcoding, no
# hand-editing role.sql), and the connection phases below reuse it too.
# ---------------------------------------------------------------------
ROLE_SQL="${SCRIPT_DIR}/database/role.sql"

role_exists() {
    PGPASSWORD="${PG_SUPERUSER_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U postgres -d postgres -t -A \
        -c "SELECT 1 FROM pg_roles WHERE rolname = '${DB_USER}';" 2>/dev/null | grep -q 1
}

echo -e "${CYAN}--- Phase 0: Role & database prerequisite (${DB_USER}) ---${NC}"
read -rsp "Password for postgres@${DB_HOST}:${DB_PORT} (superuser, needed only to check/create ${DB_USER}): " PG_SUPERUSER_PASSWORD
echo

if [[ -z "${PGPASSWORD:-}" ]]; then
    read -rsp "Password for ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME} (used now if ${DB_USER} needs creating, and for every phase below): " PGPASSWORD
    echo
    export PGPASSWORD
fi

if role_exists; then
    echo -e "${YELLOW}[SKIP]${NC} role.sql (role '${DB_USER}' already exists)"
else
    echo -e "${CYAN}[RUN]${NC} role.sql (creating role '${DB_USER}' and database '${DB_NAME}')"
    if PGPASSWORD="${PG_SUPERUSER_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U postgres -d postgres \
        -v ON_ERROR_STOP=1 -v claim_app_password="${PGPASSWORD}" -f "${ROLE_SQL}"; then
        echo -e "${GREEN}[OK]${NC} role.sql"
    else
        echo -e "${RED}[FAIL]${NC} role.sql"
        exit 1
    fi
fi

# Make claim_app own the public schema of the target database. role.sql
# creates the database OWNER claim_app, but a fresh database's public schema
# is still owned by the bootstrap superuser — and since PostgreSQL 15 that
# schema no longer grants CREATE to PUBLIC. So claim_app owns the database
# yet cannot create extensions, enum types, or tables in public until the
# schema's owner is reassigned (role.sql's header documents this intent:
# "claim_app can safely own every schema object"). This runs as the postgres
# superuser against the target DB on EVERY build — not just when role.sql
# ran — because on a rerun the role already exists and role.sql is skipped
# above. Idempotent: re-asserting the same owner is a no-op.
echo -e "${CYAN}[RUN]${NC} ALTER SCHEMA public OWNER TO ${DB_USER}"
if PGPASSWORD="${PG_SUPERUSER_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U postgres -d "${DB_NAME}" \
    -v ON_ERROR_STOP=1 -c "ALTER SCHEMA public OWNER TO ${DB_USER};"; then
    echo -e "${GREEN}[OK]${NC} public schema owner = ${DB_USER}"
else
    echo -e "${RED}[FAIL]${NC} could not reassign public schema owner to ${DB_USER}"
    exit 1
fi

unset PG_SUPERUSER_PASSWORD

PSQL="psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -v ON_ERROR_STOP=1"

total=0
failed=0
skipped=0

# PRE_EXISTING tracks (space-delimited, glob-matched — not an associative
# array: Apple's stock /bin/bash is 3.2, where `declare -A` errors with
# "invalid option") which files' representative table already existed
# BEFORE this run, so run_seed can tell "pre-existing, skip" apart from
# "created just now, seed it".
PRE_EXISTING=""

mark_preexisting() { PRE_EXISTING="${PRE_EXISTING} $1"; }
is_preexisting() {
    case " ${PRE_EXISTING} " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

table_exists() {
    local table="$1"
    local result
    result=$(${PSQL} -t -A -c "SELECT to_regclass('public.${table}') IS NOT NULL;")
    [[ "$result" == "t" ]]
}

# run_ddl(label, representative_table, file) — skips the whole file if
# its representative table already exists (marking it pre-existing for
# run_seed); otherwise applies the file in full.
run_ddl() {
    local label="$1" table="$2" file="$3"
    total=$((total + 1))
    if table_exists "$table"; then
        mark_preexisting "$table"
        echo -e "${YELLOW}[SKIP]${NC} ${label} (table '${table}' already exists)"
        skipped=$((skipped + 1))
        return
    fi
    echo -e "${CYAN}[RUN]${NC} ${label}"
    if ${PSQL} -f "$file" >/tmp/build_sh_out.$$ 2>&1; then
        echo -e "${GREEN}[OK]${NC} ${label}"
        rm -f /tmp/build_sh_out.$$
    else
        echo -e "${RED}[FAIL]${NC} ${label}"
        cat /tmp/build_sh_out.$$ >&2
        rm -f /tmp/build_sh_out.$$
        failed=$((failed + 1))
        exit 1
    fi
}

# run_sql(label, file) — for files with no CREATE TABLE to gate on
# (08_rls_policies.sql: policies + a function). Always runs; if it
# fails because the object already exists, treat that as a skip
# instead of a hard failure, so reruns stay safe.
run_sql() {
    local label="$1" file="$2"
    total=$((total + 1))
    echo -e "${CYAN}[RUN]${NC} ${label}"
    local out
    if out=$(${PSQL} -f "$file" 2>&1); then
        echo -e "${GREEN}[OK]${NC} ${label}"
    else
        if echo "$out" | grep -qiE "already exists|duplicate key value violates unique constraint"; then
            echo -e "${YELLOW}[SKIP]${NC} ${label} (already exists)"
            skipped=$((skipped + 1))
        else
            echo -e "${RED}[FAIL]${NC} ${label}"
            echo "$out" >&2
            failed=$((failed + 1))
            exit 1
        fi
    fi
}

echo -e "${CYAN}=====================================================================${NC}"
echo -e "${CYAN} Claim Settlement App — schema build${NC}"
echo -e "${CYAN} Target: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}${NC}"
echo -e "${CYAN}=====================================================================${NC}"

# ---------------------------------------------------------------------
# Phase 1 — install API Python dependencies
# ---------------------------------------------------------------------
echo -e "${CYAN}--- Phase 1: Python dependencies ---${NC}"
python3 -m pip install -r "$REQUIREMENTS_FILE"

# ---------------------------------------------------------------------
# Phase 2 — extensions & enum types (no tables; always safe to rerun,
# CREATE EXTENSION IF NOT EXISTS / CREATE TYPE both idempotent-checked
# via run_sql's already-exists skip)
# ---------------------------------------------------------------------
echo -e "${CYAN}--- Phase 2: Extensions & enum types ---${NC}"
run_sql "00_extensions.sql" "${DDL_DIR}/00_extensions.sql"

# ---------------------------------------------------------------------
# Phase 3 — tenancy (company, company_email_domain, role, company_user)
# ---------------------------------------------------------------------
echo -e "${CYAN}--- Phase 3: Tenancy ---${NC}"
run_ddl "01_tenancy.sql" "company" "${DDL_DIR}/01_tenancy.sql"

# ---------------------------------------------------------------------
# Phase 4 — reference data (currency, fx_rate — not tenant-scoped)
# ---------------------------------------------------------------------
echo -e "${CYAN}--- Phase 4: Reference data ---${NC}"
run_ddl "02_reference.sql" "currency" "${DDL_DIR}/02_reference.sql"

# ---------------------------------------------------------------------
# Phase 5 — claim type (claim_type, claim_type_field)
# ---------------------------------------------------------------------
echo -e "${CYAN}--- Phase 5: Claim type ---${NC}"
run_ddl "03_claim_type.sql" "claim_type" "${DDL_DIR}/03_claim_type.sql"

# ---------------------------------------------------------------------
# Phase 6 — approval workflow (approval_workflow, approval_level,
# approver_set_member)
# ---------------------------------------------------------------------
echo -e "${CYAN}--- Phase 6: Approval workflow ---${NC}"
run_ddl "04_approval_workflow.sql" "approval_workflow" "${DDL_DIR}/04_approval_workflow.sql"

# ---------------------------------------------------------------------
# Phase 7 — claim (claim, claim_line_item, attachment)
# ---------------------------------------------------------------------
echo -e "${CYAN}--- Phase 7: Claim ---${NC}"
run_ddl "05_claim.sql" "claim" "${DDL_DIR}/05_claim.sql"

# ---------------------------------------------------------------------
# Phase 8 — approval steps & events (approval_step, claim_event)
# ---------------------------------------------------------------------
echo -e "${CYAN}--- Phase 8: Approval steps & events ---${NC}"
run_ddl "06_approval_step_and_events.sql" "approval_step" "${DDL_DIR}/06_approval_step_and_events.sql"

# ---------------------------------------------------------------------
# Phase 9 — payment (reimbursement_payment)
# ---------------------------------------------------------------------
echo -e "${CYAN}--- Phase 9: Payment ---${NC}"
run_ddl "07_payment.sql" "reimbursement_payment" "${DDL_DIR}/07_payment.sql"

# ---------------------------------------------------------------------
# Phase 10 — RLS policies (no tables; CREATE POLICY/FUNCTION, gated via
# run_sql's already-exists skip, same as Phase 2)
# ---------------------------------------------------------------------
echo -e "${CYAN}--- Phase 10: Row-level security policies ---${NC}"
run_sql "08_rls_policies.sql" "${DDL_DIR}/08_rls_policies.sql"

# ---------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${CYAN} Build summary: ${total} total, ${GREEN}$((total - failed - skipped)) applied${NC}, ${YELLOW}${skipped} skipped${NC}, ${RED}${failed} failed${NC}"
echo -e "${CYAN}=====================================================================${NC}"

if [[ $failed -eq 0 ]]; then
    echo -e "${GREEN}Build complete.${NC}"
    exit 0
else
    echo -e "${RED}Build finished with errors.${NC}"
    exit 1
fi
