-- =====================================================================
-- seed.sql
-- Minimal local-dev seed data. The DDL in database/ddl/ intentionally
-- creates none (see CLAUDE.md), so register/login/admin-approve have
-- nothing to work against until this is run by hand.
--
-- MUST be run as the `postgres` superuser role — the same one build.sh
-- prompts for at "Password for postgres@<host>:<port>" — NOT as
-- claim_app. `company`, `role`, etc. have FORCE ROW LEVEL SECURITY
-- with a USING-only policy (e.g. `company_isolation ON company USING
-- (id = current_company_id())`); Postgres also applies that USING
-- clause as the INSERT check, which a fresh identity row can never
-- satisfy, and FORCE means even the table owner can't bypass it from a
-- normal connection. claim_app is deliberately RLS-bound and must NOT
-- be granted BYPASSRLS just to make seeding work — only a superuser
-- (or a role with BYPASSRLS, which we are not creating) can seed this
-- data.
--
--   psql -h localhost -p 5432 -U postgres -d claim_settlement_dev \
--        -f database/seed.sql
--
-- (enter the same postgres password you used in build.sh when prompted;
-- do NOT omit -U postgres — without it psql defaults to your OS
-- username, which is not the superuser and will never accept a
-- password.)
--
-- Safe to re-run: every insert is idempotent (ON CONFLICT DO NOTHING).
-- Not part of build.sh on purpose — seed data is a dev convenience, not
-- schema. Extend this file by hand if you add more companies/roles.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- currency — company.base_currency_code FK target, must exist first.
-- ---------------------------------------------------------------------
INSERT INTO currency (code, name, minor_unit_digits, is_active) VALUES
    ('USD', 'US Dollar', 2, TRUE),
    ('EUR', 'Euro',      2, TRUE),
    ('INR', 'Indian Rupee', 2, TRUE)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------------
-- company — one dev tenant.
-- ---------------------------------------------------------------------
INSERT INTO company (name, base_currency_code, allowed_claimant_types, is_active)
VALUES ('Acme Dev Co', 'USD', ARRAY['EMPLOYEE', 'NON_EMPLOYEE']::company_user_type[], TRUE)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- company_email_domain — maps an email domain to the tenant above.
-- NOT RLS-protected; this is how /auth/register resolves company_id
-- for EMPLOYEE signups before any JWT/session exists.
-- ---------------------------------------------------------------------
INSERT INTO company_email_domain (company_id, domain)
SELECT id, 'acme-dev.test' FROM company WHERE name = 'Acme Dev Co'
ON CONFLICT (domain) DO NOTHING;

-- ---------------------------------------------------------------------
-- role — the four roles the app's logic already assumes exist:
--   Admin     — gates /auth/pending-users* and GET /auth/roles
--   Claimant  — default role for an approved regular employee
--   Approver  — eligible ROLE member in approver_set_member
--   Finance   — drives payments.py's finance-review/payment routes
-- ---------------------------------------------------------------------
INSERT INTO role (company_id, name, description, is_active)
SELECT c.id, r.name, r.description, TRUE
FROM company c
CROSS JOIN (VALUES
    ('Admin',    'Approves/rejects pending registrations; full access.'),
    ('Claimant', 'Submits and tracks their own claims.'),
    ('Approver', 'Reviews and decides on claims routed to them.'),
    ('Finance',  'Initiates and reconciles reimbursement payments.')
) AS r(name, description)
WHERE c.name = 'Acme Dev Co'
ON CONFLICT (company_id, name) DO NOTHING;

COMMIT;

-- ---------------------------------------------------------------------
-- No company_user rows are seeded here on purpose: passwords must be
-- bcrypt-hashed via the API's own passlib context, not pasted in as
-- plaintext-looking SQL. Create your first user the real way:
--
--   1. POST /auth/register with an email at the seeded domain
--      (e.g. you@acme-dev.test) — lands as PENDING with role_id NULL.
--   2. Manually promote that one user to Admin + APPROVED so you have
--      someone who can approve everyone else:
--
--      UPDATE company_user
--      SET role_id = (SELECT id FROM role
--                      WHERE company_id = company_user.company_id
--                        AND name = 'Admin'),
--          approval_status = 'APPROVED'
--      WHERE auth_identity = 'you@acme-dev.test';
--
--   3. From then on, POST /auth/pending-users/{id}/approve as that
--      Admin for every subsequent signup.
-- ---------------------------------------------------------------------
