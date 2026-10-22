-- =====================================================================
-- 07_payment.sql
-- reimbursement_payment — the actual payout record.
-- "Money side" per BUSINESS_RULES.md §2 boundary principle: Finance owns
-- this table; it does not own workflow state (that's claim + approval_step).
-- =====================================================================

CREATE TABLE reimbursement_payment (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    claim_id                UUID NOT NULL REFERENCES claim (id),
    status                  payment_status NOT NULL DEFAULT 'INITIATED',

    -- Three currencies tracked independently per BUSINESS_RULES.md §5:
    -- claim's own currency, company's base/reporting currency, and the
    -- currency actually paid out (may differ from both, e.g. employee's
    -- home currency).
    payout_currency_code    CHAR(3) NOT NULL REFERENCES currency (code),
    payout_amount           NUMERIC(18, 2) NOT NULL CHECK (payout_amount > 0),
    payout_fx_rate          NUMERIC(18, 8),  -- rate from claim currency to payout currency, snapshot at initiation

    method                  TEXT NOT NULL,  -- e.g. 'BANK_TRANSFER', 'CHEQUE', 'PAYROLL'
    reference_number        TEXT,           -- bank/payroll reference, external system of record

    initiated_by_user_id    BIGINT NOT NULL REFERENCES company_user (id),
    initiated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    paid_at                 TIMESTAMPTZ,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE reimbursement_payment IS 'The actual payout record for a claim — method, reference, amount, date, status. One claim may have more than one payment row over time (e.g. a failed attempt followed by a retry).';

CREATE INDEX idx_reimbursement_payment_claim_id ON reimbursement_payment (claim_id);
CREATE INDEX idx_reimbursement_payment_status ON reimbursement_payment (status);
