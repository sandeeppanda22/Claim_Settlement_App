-- =====================================================================
-- 01_tenancy.sql
-- Root tenancy tables: company, role, company_user.
-- company_id on every tenant-scoped table downstream is a FK to company.id.
-- RLS policies for these tables live in 08_rls_policies.sql.
-- =====================================================================

-- -------------------------------------------------------------------
-- company — the tenant. Root of all tenant-scoped data.
-- -------------------------------------------------------------------
CREATE TABLE company (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                    TEXT NOT NULL,
    -- FK added in 02_reference.sql once currency exists (avoids forward ref).
    base_currency_code      CHAR(3) NOT NULL,
    -- Which company_user.user_type values this company permits to hold an
    -- account/submit claims. Default is employees-only; a company that also
    -- takes claims from external parties sets '{EMPLOYEE,NON_EMPLOYEE}'.
    -- Enforced at registration time (auth routes), not by a DB constraint,
    -- since it's a per-company runtime policy, not a structural rule.
    allowed_claimant_types  company_user_type[] NOT NULL DEFAULT ARRAY['EMPLOYEE']::company_user_type[],
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE company IS 'A purchasing organization (tenant). Root of all tenant-scoped data.';

-- -------------------------------------------------------------------
-- company_email_domain — routes an EMPLOYEE's email domain to a company
-- at login/registration time, before the caller is authenticated and
-- before app.current_company_id can be set. Deliberately NOT RLS-protected
-- (same exception as currency/fx_rate in 08_rls_policies.sql) — this table
-- only maps a domain string to a company_id, nothing tenant-sensitive.
-- -------------------------------------------------------------------
CREATE TABLE company_email_domain (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id              BIGINT NOT NULL REFERENCES company (id) ON DELETE CASCADE,
    domain                  TEXT NOT NULL UNIQUE
);

COMMENT ON TABLE company_email_domain IS 'Maps an employee email domain (e.g. acme.com) to its company, for pre-auth company resolution at login/registration.';

CREATE INDEX idx_company_email_domain_company_id ON company_email_domain (company_id);

-- -------------------------------------------------------------------
-- role — permission set within a company (Claimant, Approver, Finance, Admin).
-- Per BUSINESS_RULES.md §2, roles are always scoped to a company.
-- -------------------------------------------------------------------
CREATE TABLE role (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id              BIGINT NOT NULL REFERENCES company (id) ON DELETE CASCADE,
    name                    TEXT NOT NULL,
    description             TEXT,
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (company_id, name)
);

COMMENT ON TABLE role IS 'Permission set within a company (Claimant, Approver, Finance, Admin, ...).';

-- -------------------------------------------------------------------
-- company_user — a person who can log in under a company.
-- Employee or external claimant; both modeled the same way for v1.
-- -------------------------------------------------------------------
CREATE TABLE company_user (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id              BIGINT NOT NULL REFERENCES company (id) ON DELETE CASCADE,
    -- Nullable: a self-registered user has no role until an Admin assigns
    -- one as part of approving them (api/app/api/routes/auth.py). Must be
    -- set by the time approval_status = APPROVED — enforced below.
    role_id                 BIGINT REFERENCES role (id),
    full_name               TEXT NOT NULL,
    email                   TEXT NOT NULL,
    -- Opaque identifier matching the JWT subject claim; auth mechanism itself
    -- is out of scope for this DDL (handled at the API/auth layer).
    auth_identity           TEXT NOT NULL,
    -- Password auth (api/app/api/routes/auth.py). Hashed with passlib/bcrypt —
    -- never stored or logged in plaintext.
    password_hash           TEXT NOT NULL,
    user_type               company_user_type NOT NULL DEFAULT 'EMPLOYEE',
    -- Self-registered accounts start PENDING and can't log in until a
    -- company Admin approves them. See 00_extensions.sql comment.
    approval_status         user_approval_status NOT NULL DEFAULT 'PENDING',
    -- Set by an Admin when approval_status is moved to REJECTED
    -- (api/app/api/routes/auth.py reject_pending_user). NULL otherwise.
    rejection_reason        TEXT,
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (company_id, email),
    UNIQUE (auth_identity),
    CONSTRAINT company_user_approved_has_role
        CHECK (approval_status <> 'APPROVED' OR role_id IS NOT NULL)
);

COMMENT ON TABLE company_user IS 'A person who can log in under a company — employee or external claimant.';

CREATE INDEX idx_role_company_id ON role (company_id);
CREATE INDEX idx_company_user_company_id ON company_user (company_id);
CREATE INDEX idx_company_user_role_id ON company_user (role_id);
