-- =====================================================================
-- 04_approval_workflow.sql
-- Company-defined approval chains. See BUSINESS_RULES.md §4.
--
-- approval_workflow is keyed per claim_type; claim_type_id = NULL means
-- "company-wide fallback" (applies to any claim_type without its own
-- dedicated workflow). Enforced: at most one active dedicated workflow
-- per (company, claim_type), and at most one active fallback per company.
-- =====================================================================

CREATE TABLE approval_workflow (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id              BIGINT NOT NULL REFERENCES company (id) ON DELETE CASCADE,
    claim_type_id           BIGINT REFERENCES claim_type (id) ON DELETE CASCADE,  -- NULL = company-wide fallback
    name                    TEXT NOT NULL,
    -- Org policy, not a hard-coded behavior: when a level's amount-range
    -- routing excludes a claim, does that absence get recorded (an
    -- approval_step with decision = 'SKIPPED', for a complete audit trail)
    -- or does the claim move to the next qualifying level with no trace?
    -- Each company's workflow decides this for itself. Default TRUE to
    -- match the audit-everything posture used elsewhere, but every
    -- workflow can turn it off.
    record_skipped_levels   BOOLEAN NOT NULL DEFAULT TRUE,
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE approval_workflow IS 'Company-defined approval chain, keyed per claim_type. claim_type_id NULL = company-wide fallback used when a claim_type has no dedicated workflow.';

-- One active dedicated workflow per (company, claim_type).
CREATE UNIQUE INDEX uq_workflow_dedicated_active
    ON approval_workflow (company_id, claim_type_id)
    WHERE is_active AND claim_type_id IS NOT NULL;

-- One active fallback workflow per company.
CREATE UNIQUE INDEX uq_workflow_fallback_active
    ON approval_workflow (company_id)
    WHERE is_active AND claim_type_id IS NULL;

-- -------------------------------------------------------------------
-- approval_level — one ordered step within a workflow.
-- min_amount/max_amount implement amount-based routing: a level only
-- applies if the claim's base-currency total falls in [min, max).
-- NULL bound = unbounded on that side.
-- -------------------------------------------------------------------
CREATE TABLE approval_level (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    workflow_id             BIGINT NOT NULL REFERENCES approval_workflow (id) ON DELETE CASCADE,
    level_number            INTEGER NOT NULL CHECK (level_number > 0),
    completion_rule         approval_completion_rule NOT NULL DEFAULT 'ANY',
    min_amount              NUMERIC(18, 2),
    max_amount              NUMERIC(18, 2),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (workflow_id, level_number),
    CHECK (min_amount IS NULL OR max_amount IS NULL OR min_amount < max_amount)
);

COMMENT ON TABLE approval_level IS 'One ordered level in an approval_workflow. Levels are strictly sequential; "parallel" applies only within a level via approver_set_member + completion_rule.';

-- -------------------------------------------------------------------
-- approver_set_member — the eligible approvers for one level.
-- A level with exactly one member and completion_rule = ANY is the
-- simple single-approver case; no special-casing needed.
-- -------------------------------------------------------------------
CREATE TABLE approver_set_member (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    level_id                BIGINT NOT NULL REFERENCES approval_level (id) ON DELETE CASCADE,
    member_type             approver_member_type NOT NULL,
    role_id                 BIGINT REFERENCES role (id),
    company_user_id         BIGINT REFERENCES company_user (id),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (
        (member_type = 'ROLE' AND role_id IS NOT NULL AND company_user_id IS NULL)
        OR
        (member_type = 'USER' AND company_user_id IS NOT NULL AND role_id IS NULL)
    )
);

COMMENT ON TABLE approver_set_member IS 'One eligible approver (by role or by named person) for a given approval_level. The full set of rows for a level is its "approver set".';

CREATE INDEX idx_approval_workflow_company_id ON approval_workflow (company_id);
CREATE INDEX idx_approval_level_workflow_id ON approval_level (workflow_id);
CREATE INDEX idx_approver_set_member_level_id ON approver_set_member (level_id);
