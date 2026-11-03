-- 011i: dated performance check-ins, activated-plan gate, and activated baseline protection.
alter table public.hr_performance_checkins add column if not exists period_key text;
alter table public.hr_performance_checkins add column if not exists period_label text;
alter table public.hr_performance_checkins add column if not exists period_start date;
alter table public.hr_performance_checkins add column if not exists period_end date;
alter table public.hr_performance_checkins add column if not exists reviewer_employee_id uuid references public.hr_employees(id) on delete set null;

create or replace function public.hr_guard_performance_checkin_activation() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from public.hr_performance_reviews r where r.id=new.review_id and r.tenant_id=new.tenant_id and r.plan_status='activated' and coalesce(r.finalization_status,'draft')<>'finalized') then
   raise exception 'Check-ins are allowed only for an activated, non-finalized performance plan.';
 end if;
 return new;
end $$;
drop trigger if exists trg_hr_guard_performance_checkin_activation on public.hr_performance_checkins;
create trigger trg_hr_guard_performance_checkin_activation before insert or update of review_id,tenant_id on public.hr_performance_checkins for each row execute function public.hr_guard_performance_checkin_activation();

create or replace function public.hr_guard_activated_plan_baseline() returns trigger
language plpgsql security definer set search_path=public as $$
declare ps text;
begin
 select plan_status into ps from public.hr_performance_reviews where id=coalesce(new.review_id,old.review_id) and tenant_id=coalesce(new.tenant_id,old.tenant_id);
 if ps='activated' then
   if tg_op='DELETE' then raise exception 'Activated performance plan measures cannot be removed. Use an authorized plan amendment.'; end if;
   if tg_op='INSERT' then raise exception 'Measures cannot be added to an activated performance plan. Use an authorized plan amendment.'; end if;
   if new.metric_id is distinct from old.metric_id or new.pillar is distinct from old.pillar or new.title is distinct from old.title or new.description is distinct from old.description or new.unit is distinct from old.unit or new.direction is distinct from old.direction or new.target_value is distinct from old.target_value or new.weight is distinct from old.weight or new.due_date is distinct from old.due_date then
     raise exception 'Activated plan baseline is locked. KPI, pillar, target, weight and due date require an authorized plan amendment.';
   end if;
 end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
drop trigger if exists trg_hr_guard_activated_plan_baseline on public.hr_performance_plan_items;
create trigger trg_hr_guard_activated_plan_baseline before insert or update or delete on public.hr_performance_plan_items for each row execute function public.hr_guard_activated_plan_baseline();

create or replace function public.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_checkin uuid; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid;
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
   if not exists(select 1 from hr_performance_plan_items where id=v_item and tenant_id=p_tenant and review_id=p_review) then raise exception 'Invalid performance measure in check-in'; end if;
   insert into hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source)
   values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),'manager_observation'));
  end if;
 end loop;
 perform public.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter (where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter (where system_score is not null)/sum(weight) filter (where system_score is not null),2) end
 into v_progress from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 update hr_performance_checkins set progress_percent=v_progress where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label);
end $$;
grant execute on function public.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;
