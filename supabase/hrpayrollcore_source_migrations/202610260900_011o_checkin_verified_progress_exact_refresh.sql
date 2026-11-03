-- 011o: exact check-in verification refresh with safe single-check-in fallback.
-- Repairs the current legacy test without allowing evidence to leak between periods.

create or replace function public.hr_refresh_checkin_verified_progress(p_tenant uuid,p_checkin uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_review uuid; v_progress numeric(6,2); v_verified integer; v_total integer; v_checkin_count integer;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select review_id into v_review from hr_performance_checkins where tenant_id=p_tenant and id=p_checkin;
 if not found then raise exception 'Check-in not found'; end if;
 select count(*) into v_total from hr_performance_plan_items where tenant_id=p_tenant and review_id=v_review;
 select count(*) into v_checkin_count from hr_performance_checkins where tenant_id=p_tenant and review_id=v_review;
 with accepted as (
  select distinct on (ci.plan_item_id) ci.plan_item_id,ci.actual_value
  from hr_performance_checkin_items ci
  where ci.tenant_id=p_tenant and ci.review_id=v_review
    and (ci.checkin_id=p_checkin or (v_checkin_count=1 and (ci.checkin_id is null or ci.checkin_id<>p_checkin)))
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
 -- Permanently repair orphan/mismatched legacy submissions only when this review has one check-in.
 if v_checkin_count=1 then
  update hr_performance_checkin_items set checkin_id=p_checkin
  where tenant_id=p_tenant and review_id=v_review and checkin_id is distinct from p_checkin;
 end if;
 return jsonb_build_object('checkin_id',p_checkin,'current_verified_progress_percent',v_progress,'verified_measure_count',coalesce(v_verified,0),'total_measure_count',v_total);
end $$;
grant execute on function public.hr_refresh_checkin_verified_progress(uuid,uuid) to authenticated;

create or replace function public.hr_verify_performance_evidence_submission(p_tenant uuid,p_checkin_item uuid,p_status text,p_note text default null) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_review uuid; v_item uuid; v_checkin uuid; v_count integer;
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
 if v_checkin is null then
  select count(*), min(id::text)::uuid into v_count,v_checkin from hr_performance_checkins where tenant_id=p_tenant and review_id=v_review;
  if v_count<>1 then v_checkin=null; end if;
 end if;
 if v_checkin is not null then perform public.hr_refresh_checkin_verified_progress(p_tenant,v_checkin); end if;
 return jsonb_build_object('status',p_status,'review_id',v_review,'plan_item_id',v_item,'checkin_id',v_checkin);
end $$;
grant execute on function public.hr_verify_performance_evidence_submission(uuid,uuid,text,text) to authenticated;

