-- UniMIS: applicant offer visibility + decision-status synchronization.
-- Enables applicants to read only admission offers attached to their own applications.
-- Backfills and future-proofs application decision_status when an offer exists.

begin;

grant select on table public.admission_offers to authenticated;

drop policy if exists "Applicants can view own admission offers"
on public.admission_offers;

create policy "Applicants can view own admission offers"
on public.admission_offers
for select
to authenticated
using (
  exists (
    select 1
    from public.applications app
    join public.applicants ap on ap.id = app.applicant_id
    where app.id = admission_offers.application_id
      and ap.user_id = auth.uid()
  )
);

-- Repair existing applications where an offer was already created but
-- applications.decision_status was left at pending/under_review.
update public.applications app
set decision_status = case
      when exists (
        select 1 from public.admission_offers ao
        where ao.application_id = app.id
          and ao.response_status = 'accepted'
      ) then 'admitted'
      else 'offered'
    end,
    updated_at = now()
where exists (
  select 1
  from public.admission_offers ao
  where ao.application_id = app.id
    and ao.response_status in ('pending','accepted')
);

-- Keep the application status synchronized whenever an offer is inserted or its
-- applicant response changes.
create or replace function public.unimis_sync_application_offer_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.applications
  set decision_status = case
        when new.response_status = 'accepted' then 'admitted'
        when new.response_status = 'declined' then 'offer_declined'
        else 'offered'
      end,
      updated_at = now()
  where id = new.application_id;
  return new;
end;
$$;

drop trigger if exists trg_unimis_sync_application_offer_status
on public.admission_offers;

create trigger trg_unimis_sync_application_offer_status
after insert or update of response_status
on public.admission_offers
for each row
execute function public.unimis_sync_application_offer_status();

commit;
