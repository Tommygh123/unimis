-- 011m: preserve recorded check-in progress while separately tracking the
-- current verified weighted contribution for that exact check-in.
alter table public.hr_performance_checkins
 add column if not exists recorded_progress_percent numeric(6,2),
 add column if not exists current_verified_progress_percent numeric(6,2),
 add column if not exists verified_measure_count integer not null default 0,
 add column if not exists total_measure_count integer not null default 0,
 add column if not exists verification_progress_updated_at timestamptz;

create or replace function public.hr_refresh_checkin_verified_progress(p_tenant uuid,p_checkin uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_review uuid; v_progress numeric(6,2); v_verified integer; v_total integer;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select review_id into v_review from hr_performance_checkins where tenant_id=p_tenant and id=p_checkin;
 if not found then raise exception 'Check-in not found'; end if;
 select count(*) into v_total from hr_performance_plan_items where tenant_id=p_tenant and review_id=v_review;
 with accepted as (
  select distinct on (ci.plan_item_id) ci.plan_item_id,ci.actual_value
  from hr_performance_checkin_items ci
  where ci.tenant_id=p_tenant and ci.checkin_id=p_checkin
    and ci.verification_status in ('verified','system_verified','manager_attested')
  order by ci.plan_item_id,ci.created_at desc,ci.id desc
 ), scored as (
  select p.id,p.weight,
   case
    when a.actual_value is null or p.target_value is null then null
    when p.direction='higher_better' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
    when p.direction='lower_better' and a.actual_value=0 then 100
    when p.direction='lower_better' and a.actual_value<>0 then least(100,(p.target_value/a.actual_value)*100)
    when p.direction='pass_fail' then case when a.actual_value>=p.target_value then 100 else 0 end
    when p.direction='milestone' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
    else null end as score
  from accepted a join hr_performance_plan_items p on p.id=a.plan_item_id
  where p.tenant_id=p_tenant and p.review_id=v_review
 )
 select count(*) filter(where score is not null)::int,
        round(coalesce(sum(score*weight/100.0) filter(where score is not null),0),2)
 into v_verified,v_progress from scored;
 update hr_performance_checkins set current_verified_progress_percent=v_progress,
  verified_measure_count=coalesce(v_verified,0),total_measure_count=v_total,
  verification_progress_updated_at=now()
 where tenant_id=p_tenant and id=p_checkin;
 return jsonb_build_object('checkin_id',p_checkin,'current_verified_progress_percent',v_progress,'verified_measure_count',coalesce(v_verified,0),'total_measure_count',v_total);
end $$;
grant execute on function public.hr_refresh_checkin_verified_progress(uuid,uuid) to authenticated;

-- Wrap verification so the affected historical check-in is refreshed after the
-- evidence gate changes status. Review-level intelligence remains unchanged.
create or replace function public.hr_verify_performance_evidence_submission(p_tenant uuid,p_checkin_item uuid,p_status text,p_note text default null) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_review uuid; v_item uuid; v_checkin uuid; v_progress jsonb;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_status not in ('verified','rejected') then raise exception 'Verification status must be verified or rejected'; end if;
 if p_status='rejected' and coalesce(trim(p_note),'')='' then raise exception 'A rejection reason is required'; end if;
 update hr_performance_checkin_items set verification_status=p_status,verified_by=auth.uid(),verified_at=now(),verification_note=nullif(trim(p_note),'')
 where tenant_id=p_tenant and id=p_checkin_item and verification_status='pending'
 returning review_id,plan_item_id,checkin_id into v_review,v_item,v_checkin;
 if not found then raise exception 'Pending evidence submission was not found'; end if;
 update hr_performance_evidence_attachments set verification_status=p_status,verified_by=auth.uid(),verified_at=now()
 where tenant_id=p_tenant and review_id=v_review and plan_item_id=v_item and verification_status='pending';
 perform public.hr_performance_refresh_intelligence(p_tenant,v_review);
 v_progress:=public.hr_refresh_checkin_verified_progress(p_tenant,v_checkin);
 return jsonb_build_object('status',p_status,'review_id',v_review,'plan_item_id',v_item,'checkin_id',v_checkin,'checkin_progress',v_progress);
end $$;
grant execute on function public.hr_verify_performance_evidence_submission(uuid,uuid,text,text) to authenticated;

-- Backfill existing check-ins without depending on session membership during migration.
with totals as (
 select tenant_id,review_id,count(*)::int total_count from public.hr_performance_plan_items group by tenant_id,review_id
), accepted as (
 select distinct on (ci.checkin_id,ci.plan_item_id) ci.tenant_id,ci.checkin_id,ci.review_id,ci.plan_item_id,ci.actual_value
 from public.hr_performance_checkin_items ci
 where ci.verification_status in ('verified','system_verified','manager_attested')
 order by ci.checkin_id,ci.plan_item_id,ci.created_at desc,ci.id desc
), scored as (
 select a.tenant_id,a.checkin_id,a.review_id,p.weight,
  case
   when a.actual_value is null or p.target_value is null then null
   when p.direction='higher_better' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
   when p.direction='lower_better' and a.actual_value=0 then 100
   when p.direction='lower_better' and a.actual_value<>0 then least(100,(p.target_value/a.actual_value)*100)
   when p.direction='pass_fail' then case when a.actual_value>=p.target_value then 100 else 0 end
   when p.direction='milestone' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
   else null end score
 from accepted a join public.hr_performance_plan_items p on p.id=a.plan_item_id and p.tenant_id=a.tenant_id
), agg as (
 select tenant_id,checkin_id,review_id,count(*) filter(where score is not null)::int verified_count,
  round(coalesce(sum(score*weight/100.0) filter(where score is not null),0),2) current_progress
 from scored group by tenant_id,checkin_id,review_id
)
update public.hr_performance_checkins c set
 current_verified_progress_percent=coalesce(a.current_progress,0),
 verified_measure_count=coalesce(a.verified_count,0),
 total_measure_count=coalesce(t.total_count,0),verification_progress_updated_at=now()
from totals t left join agg a on a.tenant_id=t.tenant_id and a.review_id=t.review_id and a.checkin_id is not null
where c.tenant_id=t.tenant_id and c.review_id=t.review_id and (a.checkin_id=c.id or a.checkin_id is null);

-- Preserve the old progress snapshot as "recorded" where one exists. New rows
-- will receive a snapshot in the application/database flow below.
update public.hr_performance_checkins
set recorded_progress_percent=progress_percent
where recorded_progress_percent is null and progress_percent is not null;


create or replace function public.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_checkin uuid; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid; v_type text; v_source text; v_verification text;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select reviewer_employee_id into v_reviewer from hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and coalesce(finalization_status,'draft')<>'finalized';
 if not found then raise exception 'Review must be activated and not finalized'; end if;
 if coalesce(trim(p_period_key),'')='' then raise exception 'Check-in period is required'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'Check-in period end date cannot be before its start date'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 insert into hr_performance_checkins(tenant_id,review_id,checkin_date,period_key,period_label,period_start,period_end,reviewer_employee_id,progress_percent,status,actual_progress,achievements,blockers,evidence,support_required,next_actions)
 values(p_tenant,p_review,coalesce(p_checkin_date,current_date),p_period_key,coalesce(nullif(trim(p_period_label),''),p_period_key),p_period_start,p_period_end,v_reviewer,null,p_status,nullif(trim(p_actual_progress),''),nullif(trim(p_achievements),''),nullif(trim(p_blockers),''),nullif(trim(p_evidence),''),nullif(trim(p_support_required),''),nullif(trim(p_next_actions),'')) returning id into v_checkin;
 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   select coalesce(pi.measurement_type_snapshot,ml.measurement_type,'numeric'),coalesce(pi.data_source_snapshot,ml.data_source,'manager_verified') into v_type,v_source
   from hr_performance_plan_items pi left join hr_performance_metric_library ml on ml.id=pi.metric_id
   where pi.id=v_item and pi.tenant_id=p_tenant and pi.review_id=p_review;
   if not found then raise exception 'Invalid performance measure in check-in'; end if;
   v_verification=case when v_type='system_calculated' then 'system_verified' when v_type='behavioral_rubric' then 'manager_attested' else 'pending' end;
   if v_verification='pending' and coalesce(trim(m->>'evidence'),'')='' and not exists(select 1 from hr_performance_evidence_attachments a where a.tenant_id=p_tenant and a.review_id=p_review and a.plan_item_id=v_item) then
    raise exception 'Objective/manual source figures require evidence before submission';
   end if;
   insert into hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source,measurement_inputs,measurement_type,verification_status)
   values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),coalesce(m->'measurement_inputs','{}'::jsonb),v_type,v_verification);
  end if;
 end loop;
 perform public.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter(where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter(where system_score is not null)/sum(weight) filter(where system_score is not null),2) end into v_progress from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 perform public.hr_refresh_checkin_verified_progress(p_tenant,v_checkin);
 update hr_performance_checkins set progress_percent=current_verified_progress_percent, recorded_progress_percent=current_verified_progress_percent where id=v_checkin;
 select current_verified_progress_percent into v_progress from hr_performance_checkins where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label,'verification_required',true);
end $$;
grant execute on function public.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;
