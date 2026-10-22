-- =====================================================================
-- 03_claim_type.sql
-- Company-defined claim categories and their configurable fields.
-- =====================================================================

-- -------------------------------------------------------------------
-- claim_type — company-defined category (Travel, Medical, Advance, ...).
-- -------------------------------------------------------------------
CREATE TABLE claim_type (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id              BIGINT NOT NULL REFERENCES company (id) ON DELETE CASCADE,
    name                    TEXT NOT NULL,
    code                    TEXT NOT NULL,  -- short machine-readable key, e.g. 'TRAVEL'
    description             TEXT,
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (company_id, code)
);

COMMENT ON TABLE claim_type IS 'Company-defined claim category (Travel, Medical, Expense, Advance, ...).';

-- -------------------------------------------------------------------
-- claim_type_field — JSONB-driven field definition for a claim_type.
-- Drives the dynamic form the claimant fills in; validation_rule is JSONB
-- because its shape varies by data_type (this is the one place JSONB
-- earns its keep per ARCHITECTURE.md §3).
-- -------------------------------------------------------------------
CREATE TABLE claim_type_field (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    claim_type_id           BIGINT NOT NULL REFERENCES claim_type (id) ON DELETE CASCADE,
    field_key               TEXT NOT NULL,  -- machine key, e.g. 'destination_city'
    label                   TEXT NOT NULL,  -- display label, title case per UI convention
    data_type               TEXT NOT NULL CHECK (data_type IN ('text', 'number', 'date', 'boolean', 'select')),
    is_required             BOOLEAN NOT NULL DEFAULT FALSE,
    display_order           INTEGER NOT NULL DEFAULT 0,
    -- Shape depends on data_type, e.g. {"min":0,"max":100000} or {"options":["Economy","Business"]}.
    validation_rule         JSONB,
    -- Per-field policy cap, e.g. meal allowance max 2000/day. NULL = no cap.
    policy_limit_amount     NUMERIC(18, 2),
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (claim_type_id, field_key)
);

COMMENT ON TABLE claim_type_field IS 'JSONB-driven field definition for a claim_type (label, data type, required, validation, policy limit).';

CREATE INDEX idx_claim_type_company_id ON claim_type (company_id);
CREATE INDEX idx_claim_type_field_claim_type_id ON claim_type_field (claim_type_id);
