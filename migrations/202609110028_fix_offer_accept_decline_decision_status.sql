-- UniMIS: fix applicant offer response decision-status constraint
-- Accepting and declining an offer currently fail because
-- applications_decision_status_chk does not permit the terminal values
-- written by trg_unimis_sync_application_offer_status:
--   accepted offer -> admitted
--   declined offer -> offer_declined

begin;

alter table public.applications
  drop constraint if exists applications_decision_status_chk;

alter table public.applications
  add constraint applications_decision_status_chk
  check (
    decision_status = any (
      array[
        'pending'::text,
        'under_review'::text,
        'offered'::text,
        'admitted'::text,
        'offer_declined'::text,
        'rejected'::text,
        'waitlisted'::text,
        'withdrawn'::text
      ]
    )
  );

commit;
