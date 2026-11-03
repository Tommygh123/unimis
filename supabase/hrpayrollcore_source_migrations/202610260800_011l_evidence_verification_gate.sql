-- 011l: evidence verification gate for objective/manual PMS results.
alter table public.hr_performance_checkin_items
 add column if not exists verification_status text not null default 'pending',
 add column if not exists verified_by uuid,
 add column if not exists verified_at timestamptz,
 add column if not exists verification_note text;

do $$ begin
 if not exists(select 1 from pg_constraint where conname='hr_perf_checkin_item_verification_status_check') then
  alter table public.hr_performance_checkin_items add constraint hr_perf_checkin_item_verification_status_check
   check(verification_status in ('pending','verified','rejected','system_verified','manager_attested'));
 end if;
end $$;

-- Existing historical entries predate this gate; preserve them as verified legacy evidence.
update public.hr_performance_checkin_items set verification_status='verified'
where verification_status='pending' and created_at < now() - interval '1 minute';

create or replace function public.hr_verify_performance_evidence_submission(p_tenant uuid,p_checkin_item uuid,p_status text,p_note text default null) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_review uuid; v_item uuid;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_status not in ('verified','rejected') then raise exception 'Verification status must be verified or rejected'; end if;
 if p_status='rejected' and coalesce(trim(p_note),'')='' then raise exception 'A rejection reason is required'; end if;
 update hr_performance_checkin_items set verification_status=p_status,verified_by=auth.uid(),verified_at=now(),verification_note=nullif(trim(p_note),'')
 where tenant_id=p_tenant and id=p_checkin_item and verification_status='pending'
 returning review_id,plan_item_id into v_review,v_item;
 if not found then raise exception 'Pending evidence submission was not found'; end if;
 update hr_performance_evidence_attachments set verification_status=p_status,verified_by=auth.uid(),verified_at=now()
 where tenant_id=p_tenant and review_id=v_review and plan_item_id=v_item and verification_status='pending';
 perform public.hr_performance_refresh_intelligence(p_tenant,v_review);
 return jsonb_build_object('status',p_status,'review_id',v_review,'plan_item_id',v_item);
end $$;
grant execute on function public.hr_verify_performance_evidence_submission(uuid,uuid,text,text) to authenticated;

create or replace function public.hr_performance_refresh_intelligence(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_progress numeric(6,2); v_weight numeric(8,2); v_scored integer;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if exists(select 1 from hr_performance_reviews where tenant_id=p_tenant and id=p_review and finalization_status='finalized') then raise exception 'Finalized appraisal is locked'; end if;

 -- Only verified/system-verified/manager-attested results may become the authoritative actual.
 with latest as (
  select distinct on (plan_item_id) plan_item_id,actual_value,evidence_source
  from hr_performance_checkin_items
  where tenant_id=p_tenant and review_id=p_review and verification_status in ('verified','system_verified','manager_attested')
  order by plan_item_id,created_at desc,id desc
 ), counts as (
  select plan_item_id,count(*)::int evidence_count from hr_performance_checkin_items
  where tenant_id=p_tenant and review_id=p_review and verification_status in ('verified','system_verified','manager_attested') group by plan_item_id
 )
 update hr_performance_plan_items p set
  actual_value=l.actual_value,
  latest_evidence_source=l.evidence_source,
  evidence_count=coalesce(c.evidence_count,0)
 from latest l left join counts c on c.plan_item_id=l.plan_item_id
 where p.tenant_id=p_tenant and p.review_id=p_review and p.id=l.plan_item_id;

 -- If an item has submissions but none accepted, do not let pending/rejected facts become a score.
 update hr_performance_plan_items p set actual_value=null,system_score=null,evidence_count=0
 where p.tenant_id=p_tenant and p.review_id=p_review
 and exists(select 1 from hr_performance_checkin_items ci where ci.tenant_id=p_tenant and ci.review_id=p_review and ci.plan_item_id=p.id)
 and not exists(select 1 from hr_performance_checkin_items ci where ci.tenant_id=p_tenant and ci.review_id=p_review and ci.plan_item_id=p.id and ci.verification_status in ('verified','system_verified','manager_attested'));

 update hr_performance_plan_items set
  system_score=case
   when actual_value is null or target_value is null then null
   when direction='higher_better' and target_value<>0 then round(least(100,(actual_value/target_value)*100),2)
   when direction='lower_better' and actual_value=0 then 100
   when direction='lower_better' and actual_value<>0 then round(least(100,(target_value/actual_value)*100),2)
   when direction='pass_fail' then case when actual_value>=target_value then 100 else 0 end
   when direction='milestone' and target_value<>0 then round(least(100,(actual_value/target_value)*100),2)
   else null end,
  scoring_source='system',
  integrity_flag=case when actual_value is not null and evidence_count=0 then 'review' when supervisor_validation='disputed' then 'review' else 'normal' end
 where tenant_id=p_tenant and review_id=p_review;
 get diagnostics v_scored=row_count;
 select coalesce(sum(weight),0),case when coalesce(sum(weight) filter(where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter(where system_score is not null)/sum(weight) filter(where system_score is not null),2) end
 into v_weight,v_progress from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 return jsonb_build_object('items_scored',v_scored,'progress_percent',v_progress,'plan_weight',v_weight);
end $$;
grant execute on function public.hr_performance_refresh_intelligence(uuid,uuid) to authenticated;

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
 update hr_performance_checkins set progress_percent=v_progress where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label,'verification_required',true);
end $$;
grant execute on function public.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;
