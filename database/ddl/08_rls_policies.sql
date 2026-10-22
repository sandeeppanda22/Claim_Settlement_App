-- =====================================================================
-- 08_rls_policies.sql
-- Row-Level Security: every tenant-scoped table is isolated by
-- current_setting('app.current_company_id'), set once per request by
-- the FastAPI backend after JWT verification. See ARCHITECTURE.md §4.
--
-- Pattern:
--   1. ALTER TABLE ... ENABLE ROW LEVEL SECURITY  (and FORCE, so even the
--      table owner can't bypass it from app_backend's own connection).
--   2. One policy per table comparing company_id to the session setting.
--
-- Tables with a direct company_id column get a simple equality policy.
-- Tables one hop away from company_id (e.g. claim_line_item has no
-- company_id of its own) get a policy via EXISTS against the parent.
-- =====================================================================

-- Helper: cast once, reused by every policy below. current_setting's
-- third argument (true) means "return NULL instead of erroring if unset" —
-- NULL never equals any company_id, so an unset session sees zero rows
-- (fail closed, not fail open).
CREATE OR REPLACE FUNCTION current_company_id() RETURNS BIGINT
    LANGUAGE sql STABLE AS
$$
    SELECT current_setting('app.current_company_id', true)::BIGINT;
$$;

-- -------------------------------------------------------------------
-- Direct company_id column
-- -------------------------------------------------------------------

ALTER TABLE company ENABLE ROW LEVEL SECURITY;
ALTER TABLE company FORCE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON company
    USING (id = current_company_id());

ALTER TABLE role ENABLE ROW LEVEL SECURITY;
ALTER TABLE role FORCE ROW LEVEL SECURITY;
CREATE POLICY role_isolation ON role
    USING (company_id = current_company_id());

ALTER TABLE company_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_user FORCE ROW LEVEL SECURITY;
CREATE POLICY company_user_isolation ON company_user
    USING (company_id = current_company_id());

ALTER TABLE claim_type ENABLE ROW LEVEL SECURITY;
ALTER TABLE claim_type FORCE ROW LEVEL SECURITY;
CREATE POLICY claim_type_isolation ON claim_type
    USING (company_id = current_company_id());

ALTER TABLE approval_workflow ENABLE ROW LEVEL SECURITY;
ALTER TABLE approval_workflow FORCE ROW LEVEL SECURITY;
CREATE POLICY approval_workflow_isolation ON approval_workflow
    USING (company_id = current_company_id());

ALTER TABLE claim ENABLE ROW LEVEL SECURITY;
ALTER TABLE claim FORCE ROW LEVEL SECURITY;
CREATE POLICY claim_isolation ON claim
    USING (company_id = current_company_id());

-- -------------------------------------------------------------------
-- One hop from company_id — scoped via EXISTS against the parent table.
-- -------------------------------------------------------------------

ALTER TABLE claim_type_field ENABLE ROW LEVEL SECURITY;
ALTER TABLE claim_type_field FORCE ROW LEVEL SECURITY;
CREATE POLICY claim_type_field_isolation ON claim_type_field
    USING (EXISTS (
        SELECT 1 FROM claim_type ct
        WHERE ct.id = claim_type_field.claim_type_id
          AND ct.company_id = current_company_id()
    ));

ALTER TABLE approval_level ENABLE ROW LEVEL SECURITY;
ALTER TABLE approval_level FORCE ROW LEVEL SECURITY;
CREATE POLICY approval_level_isolation ON approval_level
    USING (EXISTS (
        SELECT 1 FROM approval_workflow w
        WHERE w.id = approval_level.workflow_id
          AND w.company_id = current_company_id()
    ));

ALTER TABLE approver_set_member ENABLE ROW LEVEL SECURITY;
ALTER TABLE approver_set_member FORCE ROW LEVEL SECURITY;
CREATE POLICY approver_set_member_isolation ON approver_set_member
    USING (EXISTS (
        SELECT 1 FROM approval_level l
        JOIN approval_workflow w ON w.id = l.workflow_id
        WHERE l.id = approver_set_member.level_id
          AND w.company_id = current_company_id()
    ));

ALTER TABLE claim_line_item ENABLE ROW LEVEL SECURITY;
ALTER TABLE claim_line_item FORCE ROW LEVEL SECURITY;
CREATE POLICY claim_line_item_isolation ON claim_line_item
    USING (EXISTS (
        SELECT 1 FROM claim c
        WHERE c.id = claim_line_item.claim_id
          AND c.company_id = current_company_id()
    ));

ALTER TABLE attachment ENABLE ROW LEVEL SECURITY;
ALTER TABLE attachment FORCE ROW LEVEL SECURITY;
CREATE POLICY attachment_isolation ON attachment
    USING (EXISTS (
        SELECT 1 FROM claim c
        WHERE c.id = attachment.claim_id
          AND c.company_id = current_company_id()
    ));

ALTER TABLE approval_step ENABLE ROW LEVEL SECURITY;
ALTER TABLE approval_step FORCE ROW LEVEL SECURITY;
CREATE POLICY approval_step_isolation ON approval_step
    USING (EXISTS (
        SELECT 1 FROM claim c
        WHERE c.id = approval_step.claim_id
          AND c.company_id = current_company_id()
    ));

ALTER TABLE claim_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE claim_event FORCE ROW LEVEL SECURITY;
CREATE POLICY claim_event_isolation ON claim_event
    USING (EXISTS (
        SELECT 1 FROM claim c
        WHERE c.id = claim_event.claim_id
          AND c.company_id = current_company_id()
    ));

ALTER TABLE reimbursement_payment ENABLE ROW LEVEL SECURITY;
ALTER TABLE reimbursement_payment FORCE ROW LEVEL SECURITY;
CREATE POLICY reimbursement_payment_isolation ON reimbursement_payment
    USING (EXISTS (
        SELECT 1 FROM claim c
        WHERE c.id = reimbursement_payment.claim_id
          AND c.company_id = current_company_id()
    ));

-- -------------------------------------------------------------------
-- NOT tenant-scoped — intentionally no RLS: currency, fx_rate are
-- global reference data (ARCHITECTURE.md §9.6, OPEN/PENDING on whether
-- fx_rate ever becomes per-company).
-- -------------------------------------------------------------------
