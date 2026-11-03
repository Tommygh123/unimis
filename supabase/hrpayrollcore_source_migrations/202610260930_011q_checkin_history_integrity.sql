-- 011q: consolidate accidental duplicate scheduled check-ins and enforce period integrity.
-- Canonical row preference: linked evidence first, then verified progress, then earliest creation.
-- Evidence is re-linked before duplicate check-in rows are removed, preserving the audit trail.

do $$
declare r record;
begin
  for r in
    with linked as (
      select c.id,c.tenant_id,c.review_id,c.period_key,c.created_at,
             c.current_verified_progress_percent,
             (select count(*) from public.hr_performance_checkin_items i where i.checkin_id=c.id) +
             (select count(*) from public.hr_performance_evidence_attachments a where a.checkin_id=c.id) as link_count
      from public.hr_performance_checkins c
      where coalesce(c.period_key,'')<>'' and upper(c.period_key)<>'ADHOC'
    ), ranked as (
      select l.*,
             first_value(id) over (
               partition by tenant_id,review_id,period_key
               order by link_count desc,current_verified_progress_percent desc nulls last,created_at asc,id
             ) as keep_id,
             row_number() over (
               partition by tenant_id,review_id,period_key
               order by link_count desc,current_verified_progress_percent desc nulls last,created_at asc,id
             ) as rn
      from linked l
    )
    select id as duplicate_id,keep_id
    from ranked where rn>1
  loop
    update public.hr_performance_checkin_items
       set checkin_id=r.keep_id
     where checkin_id=r.duplicate_id;

    update public.hr_performance_evidence_attachments
       set checkin_id=r.keep_id
     where checkin_id=r.duplicate_id;

    delete from public.hr_performance_checkins
     where id=r.duplicate_id;
  end loop;
end $$;

-- Database-level guarantee in addition to the friendly trigger message.
create unique index if not exists uq_hr_performance_checkins_scheduled_period
on public.hr_performance_checkins(tenant_id,review_id,period_key)
where coalesce(period_key,'')<>'' and upper(period_key)<>'ADHOC';
