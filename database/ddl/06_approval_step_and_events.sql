-- =====================================================================
-- 06_approval_step_and_events.sql
-- approval_step: one level's outcome for one claim.
-- claim_event: immutable audit log of every state transition.
-- =====================================================================

-- -------------------------------------------------------------------
-- approval_step — one level's outcome for one claim.
-- Created server-side when a claim enters a level (never client-originated),
-- hence bigint identity per ARCHITECTURE.md §8.
-- One row per (claim, level, approver) — supports the ALL completion rule
-- where multiple approvers in the same set each record their own decision.
-- -------------------------------------------------------------------
CREATE TABLE approval_step (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    claim_id                UUID NOT NULL REFERENCES claim (id) ON DELETE CASCADE,
    level_id                BIGINT NOT NULL REFERENCES approval_level (id),
    approver_user_id        BIGINT REFERENCES company_user (id),  -- NULL until someone acts (ANY rule: first to act wins)
    decision                approval_decision NOT NULL DEFAULT 'PENDING',
    comment                 TEXT,
    decided_at              TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (claim_id, level_id, approver_user_id)
);

COMMENT ON TABLE approval_step IS 'One level''s outcome for one claim — approver, decision, timestamp, comment. Multiple rows per (claim, level) when the level''s completion_rule is ALL.';

-- -------------------------------------------------------------------
-- claim_event — immutable audit log. Every state transition, every actor,
-- every timestamp. No transition is silent (BUSINESS_RULES.md §3).
-- UUID per ARCHITECTURE.md §8 — client may originate events offline
-- (e.g. a claimant edits a Draft with no connectivity).
-- -------------------------------------------------------------------
CREATE TABLE claim_event (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    claim_id                UUID NOT NULL REFERENCES claim (id) ON DELETE CASCADE,
    event_type              TEXT NOT NULL,  -- e.g. 'SUBMITTED', 'LEVEL_APPROVED', 'RETURNED_FOR_REVISION'
    from_status             claim_status,
    to_status               claim_status NOT NULL,
    actor_company_user_id   BIGINT REFERENCES company_user (id),  -- NULL for system-generated events
    comment                 TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE claim_event IS 'Immutable audit log — every state transition, every actor, every timestamp. This is the traceability layer tying claim + approval_step (communication) to reimbursement_payment (money).';

-- No UPDATE/DELETE should ever be issued against claim_event from the
-- application; enforced at the app_backend role grant level (see
-- 08_rls_policies.sql), not restated here as a trigger to avoid
-- duplicating enforcement logic in two places.

CREATE INDEX idx_approval_step_claim_id ON approval_step (claim_id);
CREATE INDEX idx_approval_step_level_id ON approval_step (level_id);
CREATE INDEX idx_claim_event_claim_id ON claim_event (claim_id);
CREATE INDEX idx_claim_event_created_at ON claim_event (created_at);
