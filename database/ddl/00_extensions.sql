-- =====================================================================
-- 00_extensions.sql
-- Extensions and shared enum types used across the Claim Settlement App.
-- Run first, before any table DDL.
-- =====================================================================

-- UUID generation for client-originable entities (claim, claim_line_item,
-- attachment, claim_event, reimbursement_payment). See ARCHITECTURE.md §8.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -------------------------------------------------------------------
-- Shared enum types
-- -------------------------------------------------------------------

-- Approval engine: how a level with multiple eligible approvers clears.
-- See BUSINESS_RULES.md §4.
CREATE TYPE approval_completion_rule AS ENUM ('ANY', 'ALL');

-- An approver_set_member is either a named person or anyone holding a role.
CREATE TYPE approver_member_type AS ENUM ('ROLE', 'USER');

-- Claim lifecycle states. See BUSINESS_RULES.md §3.
CREATE TYPE claim_status AS ENUM (
    'DRAFT',
    'SUBMITTED',
    'PENDING_APPROVAL',
    'APPROVED',
    'REJECTED',
    'RETURNED_FOR_REVISION',
    'PENDING_FINANCE_REVIEW',
    'PAYMENT_INITIATED',
    'REIMBURSED',
    'CLOSED',
    'CANCELLED'
);

-- Outcome of a single approval_step. SKIPPED = the level's amount-range
-- routing excluded this claim; only ever written when the owning
-- approval_workflow has record_skipped_levels = TRUE (see 04_approval_workflow.sql
-- and BUSINESS_RULES.md §4 — this is a per-company policy choice, not hard-coded).
-- RETURNED_FOR_REVISION = the approver sent the claim back for the claimant
-- to fix and resubmit, distinct from REJECTED (which ends the claim) and
-- from PENDING (no decision made yet). See BUSINESS_RULES.md §3.
CREATE TYPE approval_decision AS ENUM (
    'PENDING', 'APPROVED', 'REJECTED', 'SKIPPED', 'RETURNED_FOR_REVISION'
);

-- reimbursement_payment status.
CREATE TYPE payment_status AS ENUM ('INITIATED', 'PAID', 'FAILED', 'CANCELLED');

-- company_user.user_type — EMPLOYEE resolves its company at login via email
-- domain (company_email_domain); NON_EMPLOYEE must supply company_id
-- explicitly, since a personal email has no company domain to resolve from.
-- See ARCHITECTURE.md auth slice notes.
CREATE TYPE company_user_type AS ENUM ('EMPLOYEE', 'NON_EMPLOYEE');

-- company_user.approval_status — a self-registered account starts PENDING
-- and cannot log in until a company Admin approves it (or rejects it).
-- Admin-created accounts (future admin-invite flow) are inserted as
-- APPROVED directly, skipping this gate.
CREATE TYPE user_approval_status AS ENUM ('PENDING', 'APPROVED', 'REJECTED');
