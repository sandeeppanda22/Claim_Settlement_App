-- =====================================================================
-- 05_claim.sql
-- The claim itself, its line items, and attachments.
-- UUID primary keys — these are the entities a claimant could originate
-- offline (see ARCHITECTURE.md §8).
-- =====================================================================

-- -------------------------------------------------------------------
-- claim — a single claim submitted by a user, of one claim_type.
-- Single-currency per BUSINESS_RULES.md §5 / confirmed decision: a claim
-- is filed in exactly one currency; line items do not carry their own
-- currency, they inherit the claim's.
-- -------------------------------------------------------------------
CREATE TABLE claim (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              BIGINT NOT NULL REFERENCES company (id),
    claim_type_id           BIGINT NOT NULL REFERENCES claim_type (id),
    company_user_id         BIGINT NOT NULL REFERENCES company_user (id),  -- the claimant
    status                  claim_status NOT NULL DEFAULT 'DRAFT',

    title                   TEXT NOT NULL,
    description             TEXT,

    -- Currency the claimant filed in, and the snapshot FX used to convert
    -- to company base currency at submission time (never recomputed later).
    claim_currency_code     CHAR(3) NOT NULL REFERENCES currency (code),
    fx_rate_to_base         NUMERIC(18, 8),      -- NULL until submitted
    base_currency_code      CHAR(3) REFERENCES currency (code),  -- snapshot of company base currency at submission

    -- Denormalized total, maintained by application/trigger from line items.
    total_amount            NUMERIC(18, 2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),

    -- Which approval_level this claim is currently sitting at, if any.
    current_level_id        BIGINT REFERENCES approval_level (id),

    submitted_at            TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE claim IS 'A single claim submitted by a user, of one claim_type. Single-currency: all line items inherit claim_currency_code.';

-- -------------------------------------------------------------------
-- claim_line_item — individual expense lines within a claim.
-- -------------------------------------------------------------------
CREATE TABLE claim_line_item (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    claim_id                UUID NOT NULL REFERENCES claim (id) ON DELETE CASCADE,
    line_number             INTEGER NOT NULL CHECK (line_number > 0),
    expense_date            DATE NOT NULL,
    category                TEXT NOT NULL,  -- e.g. 'Airfare', 'Lodging', 'Meals'
    description             TEXT,
    amount                  NUMERIC(18, 2) NOT NULL CHECK (amount > 0),
    -- Free-form answers for this claim_type's claim_type_field definitions.
    field_values             JSONB,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (claim_id, line_number)
);

COMMENT ON TABLE claim_line_item IS 'Individual expense lines within a claim (date, category, amount, description). Currency inherited from parent claim.';

-- -------------------------------------------------------------------
-- attachment — receipt/file linked to a claim or line item.
-- Manual-entry claims may have none (see BUSINESS_RULES.md §6).
-- -------------------------------------------------------------------
CREATE TABLE attachment (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    claim_id                UUID NOT NULL REFERENCES claim (id) ON DELETE CASCADE,
    claim_line_item_id      UUID REFERENCES claim_line_item (id) ON DELETE CASCADE,
    file_name               TEXT NOT NULL,
    storage_path            TEXT NOT NULL,  -- object storage key/URL, not file bytes
    content_type            TEXT,
    uploaded_by_user_id     BIGINT NOT NULL REFERENCES company_user (id),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE attachment IS 'Receipt/file linked to a claim or line item. OCR extraction is phase 2, not v1 (BUSINESS_RULES.md §6).';

CREATE INDEX idx_claim_company_id ON claim (company_id);
CREATE INDEX idx_claim_company_user_id ON claim (company_user_id);
CREATE INDEX idx_claim_claim_type_id ON claim (claim_type_id);
CREATE INDEX idx_claim_status ON claim (status);
CREATE INDEX idx_claim_line_item_claim_id ON claim_line_item (claim_id);
CREATE INDEX idx_attachment_claim_id ON attachment (claim_id);
CREATE INDEX idx_attachment_claim_line_item_id ON attachment (claim_line_item_id);
