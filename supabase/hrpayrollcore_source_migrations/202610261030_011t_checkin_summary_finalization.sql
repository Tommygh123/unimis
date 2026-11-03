-- 011t: check-in summary and finalization lifecycle.
alter table public.hr_performance_checkins
 add column if not exists finalization_status text not null default 'open',
 add column if not exists finalized_at timestamptz,
 add column if not exists finalized_by uuid,
 add column if not exists status_override_reason text;

do $$ begin
 if not exists(select 1 from pg_constraint where conname='hr_performance_checkins_finalization_status_check') then
  alter table public.hr_performance_checkins add constraint hr_performance_checkins_finalization_status_check check(finalization_status in ('open','finalized'));
 end if;
end $$;

-- Recorded Progress is a frozen finalization snapshot, not a live value.
update public.hr_performance_checkins set recorded_progress_percent=null
where finalization_status='open';

create or replace function public.hr_save_performance_checkin_summary(
 p_tenant uuid,p_checkin uuid,p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_override_reason text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare c record; v_suggested text;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into c from hr_performance_checkins where tenant_id=p_tenant and id=p_checkin for update;
 if not found then raise exception 'Check-in not found'; end if;
 if c.finalization_status='finalized' then raise exception 'This check-in is finalized and locked'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 if length(coalesce(trim(p_actual_progress),''))<10 then raise exception 'Add a brief overall progress/result summary'; end if;
 if coalesce(c.verified_measure_count,0)=coalesce(c.total_measure_count,0) and coalesce(c.total_measure_count,0)>0 then
  v_suggested=case when coalesce(c.current_verified_progress_percent,0)>=100 then 'exceeded' when c.current_verified_progress_percent>=75 then 'on_track' when c.current_verified_progress_percent>=50 then 'at_risk' else 'off_track' end;
 end if;
 if v_suggested is not null and p_status<>v_suggested and length(coalesce(trim(p_override_reason),''))<10 then raise exception 'Explain why the supervisor status differs from the system suggestion'; end if;
 update hr_performance_checkins set status=p_status,actual_progress=nullif(trim(p_actual_progress),''),achievements=nullif(trim(p_achievements),''),blockers=nullif(trim(p_blockers),''),evidence=nullif(trim(p_evidence),''),support_required=nullif(trim(p_support_required),''),next_actions=nullif(trim(p_next_actions),''),status_override_reason=case when v_suggested is not null and p_status<>v_suggested then nullif(trim(p_override_reason),'') else null end where id=p_checkin and tenant_id=p_tenant;
 return jsonb_build_object('checkin_id',p_checkin,'suggested_status',v_suggested,'status',p_status,'summary_saved',true);
end $$;
grant execute on function public.hr_save_performance_checkin_summary(uuid,uuid,text,text,text,text,text,text,text,text) to authenticated;

create or replace function public.hr_finalize_performance_checkin(p_tenant uuid,p_checkin uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c record;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into c from hr_performance_checkins where tenant_id=p_tenant and id=p_checkin for update;
 if not found then raise exception 'Check-in not found'; end if;
 if c.finalization_status='finalized' then return jsonb_build_object('checkin_id',p_checkin,'already_finalized',true,'recorded_progress_percent',c.recorded_progress_percent); end if;
 perform public.hr_refresh_checkin_verified_progress(p_tenant,p_checkin);
 select * into c from hr_performance_checkins where tenant_id=p_tenant and id=p_checkin for update;
 if coalesce(c.total_measure_count,0)=0 or coalesce(c.verified_measure_count,0)<>c.total_measure_count then raise exception 'All performance measures must be verified before finalizing this check-in (% of % verified)',coalesce(c.verified_measure_count,0),coalesce(c.total_measure_count,0); end if;
 if length(coalesce(trim(c.actual_progress),''))<10 then raise exception 'Complete the Check-in Summary before finalizing'; end if;
 update hr_performance_checkins set recorded_progress_percent=current_verified_progress_percent,progress_percent=current_verified_progress_percent,finalization_status='finalized',finalized_at=now(),finalized_by=auth.uid() where tenant_id=p_tenant and id=p_checkin;
 return jsonb_build_object('checkin_id',p_checkin,'finalized',true,'recorded_progress_percent',c.current_verified_progress_percent);
end $$;
grant execute on function public.hr_finalize_performance_checkin(uuid,uuid) to authenticated;

-- 011r continuation, corrected: live evidence refresh must not overwrite Recorded Progress.
create or replace function public.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_checkin uuid; v_existing_item uuid; v_existing_verification text; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid; v_type text; v_source text; v_verification text; v_reused boolean:=false; v_final text;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select reviewer_employee_id into v_reviewer from hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and coalesce(finalization_status,'draft')<>'finalized';
 if not found then raise exception 'Review must be activated and not finalized'; end if;
 if coalesce(trim(p_period_key),'')='' then raise exception 'Check-in period is required'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'Check-in period end date cannot be before its start date'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 if upper(p_period_key)<>'ADHOC' then select id,finalization_status into v_checkin,v_final from hr_performance_checkins where tenant_id=p_tenant and review_id=p_review and period_key=p_period_key order by created_at asc limit 1; end if;
 if v_final='finalized' then raise exception 'This check-in period is finalized and locked'; end if;
 if v_checkin is null then insert into hr_performance_checkins(tenant_id,review_id,checkin_date,period_key,period_label,period_start,period_end,reviewer_employee_id,progress_percent,status) values(p_tenant,p_review,coalesce(p_checkin_date,current_date),p_period_key,coalesce(nullif(trim(p_period_label),''),p_period_key),p_period_start,p_period_end,v_reviewer,null,p_status) returning id into v_checkin; else v_reused:=true; end if;
 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   select coalesce(pi.measurement_type_snapshot,ml.measurement_type,'numeric'),coalesce(pi.data_source_snapshot,ml.data_source,'manager_verified') into v_type,v_source from hr_performance_plan_items pi left join hr_performance_metric_library ml on ml.id=pi.metric_id where pi.id=v_item and pi.tenant_id=p_tenant and pi.review_id=p_review;
   if not found then raise exception 'Invalid performance measure in check-in'; end if;
   v_verification=case when v_type='system_calculated' then 'system_verified' when v_type='behavioral_rubric' then 'manager_attested' else 'pending' end;
   if v_verification='pending' and coalesce(trim(m->>'evidence'),'')='' and not exists(select 1 from hr_performance_evidence_attachments a where a.tenant_id=p_tenant and a.review_id=p_review and a.plan_item_id=v_item) then raise exception 'Objective/manual source figures require evidence before submission'; end if;
   v_existing_item:=null;v_existing_verification:=null;
   select id,verification_status into v_existing_item,v_existing_verification from hr_performance_checkin_items where tenant_id=p_tenant and checkin_id=v_checkin and plan_item_id=v_item order by created_at desc limit 1;
   if v_existing_item is null then insert into hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source,measurement_inputs,measurement_type,verification_status) values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),coalesce(m->'measurement_inputs','{}'::jsonb),v_type,v_verification);
   elsif v_existing_verification in ('verified','system_verified') then null;
   else update hr_performance_checkin_items set actual_value=v_actual,evidence=nullif(trim(m->>'evidence'),''),evidence_source=coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),measurement_inputs=coalesce(m->'measurement_inputs','{}'::jsonb),measurement_type=v_type,verification_status=v_verification,verified_by=null,verified_at=null,verification_note=null where id=v_existing_item; end if;
  end if;
 end loop;
 perform public.hr_performance_refresh_intelligence(p_tenant,p_review); perform public.hr_refresh_checkin_verified_progress(p_tenant,v_checkin);
 update hr_performance_checkins set progress_percent=current_verified_progress_percent where id=v_checkin;
 select current_verified_progress_percent into v_progress from hr_performance_checkins where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label,'verification_required',true,'reused_existing',v_reused);
end $$;
grant execute on function public.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;
