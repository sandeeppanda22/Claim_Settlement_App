-- =====================================================================
-- 02_reference.sql
-- Global reference data: currency, fx_rate.
-- OPEN/PENDING (see ARCHITECTURE.md §9.6): fx_rate is modeled as global
-- for v1. Whether a company can override its own negotiated rate is not
-- yet decided — flagged for confirmation, not silently decided.
-- =====================================================================

-- -------------------------------------------------------------------
-- currency — supported ISO 4217 currencies. Natural key (no surrogate id).
-- -------------------------------------------------------------------
CREATE TABLE currency (
    code                    CHAR(3) PRIMARY KEY,  -- ISO 4217, e.g. 'USD', 'EUR', 'INR'
    name                    TEXT NOT NULL,
    minor_unit_digits       SMALLINT NOT NULL DEFAULT 2,  -- e.g. 0 for JPY, 2 for USD
    is_active               BOOLEAN NOT NULL DEFAULT TRUE
);

COMMENT ON TABLE currency IS 'Supported currencies (ISO 4217). Global reference data, not company-scoped.';

-- Now that currency exists, add the deferred FK from company.
ALTER TABLE company
    ADD CONSTRAINT fk_company_base_currency
    FOREIGN KEY (base_currency_code) REFERENCES currency (code);

-- -------------------------------------------------------------------
-- fx_rate — exchange rate snapshots used to convert claim currency to
-- company base currency at submission time. See BUSINESS_RULES.md §5.
-- -------------------------------------------------------------------
CREATE TABLE fx_rate (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    from_currency_code      CHAR(3) NOT NULL REFERENCES currency (code),
    to_currency_code        CHAR(3) NOT NULL REFERENCES currency (code),
    rate                    NUMERIC(18, 8) NOT NULL CHECK (rate > 0),
    as_of_date              DATE NOT NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (from_currency_code, to_currency_code, as_of_date),
    CHECK (from_currency_code <> to_currency_code)
);

COMMENT ON TABLE fx_rate IS 'Daily exchange-rate snapshots. A claim stores the rate it used at submission time, so later rate changes never retroactively alter an already-submitted claim''s reported value.';

CREATE INDEX idx_fx_rate_lookup ON fx_rate (from_currency_code, to_currency_code, as_of_date DESC);
