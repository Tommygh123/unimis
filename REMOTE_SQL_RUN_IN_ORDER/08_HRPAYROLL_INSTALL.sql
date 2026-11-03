-- CONTINUATION: UniMIS Build 172 HR/Payroll repair
set search_path=unimis,public;

-- SOURCE 202610251140_011i_checkin_periods_activation_guard.sql
-- 011i: dated performance check-ins, activated-plan gate, and activated baseline protection.
alter table unimis.hrc_hr_performance_checkins add column if not exists period_key text;
alter table unimis.hrc_hr_performance_checkins add column if not exists period_label text;
alter table unimis.hrc_hr_performance_checkins add column if not exists period_start date;
alter table unimis.hrc_hr_performance_checkins add column if not exists period_end date;
alter table unimis.hrc_hr_performance_checkins add column if not exists reviewer_employee_id uuid references unimis.hrc_hr_employees(id) on delete set null;

create or replace function unimis.hr_guard_performance_checkin_activation() returns trigger
language plpgsql security definer set search_path=unimis as $$
begin
 if not exists(select 1 from unimis.hrc_hr_performance_reviews r where r.id=new.review_id and r.tenant_id=new.tenant_id and r.plan_status='activated' and coalesce(r.finalization_status,'draft')<>'finalized') then
   raise exception 'Check-ins are allowed only for an activated, non-finalized performance plan.';
 end if;
 return new;
end $$;
drop trigger if exists trg_hr_guard_performance_checkin_activation on unimis.hrc_hr_performance_checkins;
create trigger trg_hr_guard_performance_checkin_activation before insert or update of review_id,tenant_id on unimis.hrc_hr_performance_checkins for each row execute function unimis.hr_guard_performance_checkin_activation();

create or replace function unimis.hr_guard_activated_plan_baseline() returns trigger
language plpgsql security definer set search_path=unimis as $$
declare ps text;
begin
 select plan_status into ps from unimis.hrc_hr_performance_reviews where id=coalesce(new.review_id,old.review_id) and tenant_id=coalesce(new.tenant_id,old.tenant_id);
 if ps='activated' then
   if tg_op='DELETE' then raise exception 'Activated performance plan measures cannot be removed. Use an authorized plan amendment.'; end if;
   if tg_op='INSERT' then raise exception 'Measures cannot be added to an activated performance plan. Use an authorized plan amendment.'; end if;
   if new.metric_id is distinct from old.metric_id or new.pillar is distinct from old.pillar or new.title is distinct from old.title or new.description is distinct from old.description or new.unit is distinct from old.unit or new.direction is distinct from old.direction or new.target_value is distinct from old.target_value or new.weight is distinct from old.weight or new.due_date is distinct from old.due_date then
     raise exception 'Activated plan baseline is locked. KPI, pillar, target, weight and due date require an authorized plan amendment.';
   end if;
 end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
drop trigger if exists trg_hr_guard_activated_plan_baseline on unimis.hrc_hr_performance_plan_items;
create trigger trg_hr_guard_activated_plan_baseline before insert or update or delete on unimis.hrc_hr_performance_plan_items for each row execute function unimis.hr_guard_activated_plan_baseline();

create or replace function unimis.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare v_checkin uuid; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select reviewer_employee_id into v_reviewer from hrc_hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and coalesce(finalization_status,'draft')<>'finalized';
 if not found then raise exception 'Review must be activated and not finalized'; end if;
 if coalesce(trim(p_period_key),'')='' then raise exception 'Check-in period is required'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'Check-in period end date cannot be before its start date'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 insert into hrc_hr_performance_checkins(tenant_id,review_id,checkin_date,period_key,period_label,period_start,period_end,reviewer_employee_id,progress_percent,status,actual_progress,achievements,blockers,evidence,support_required,next_actions)
 values(p_tenant,p_review,coalesce(p_checkin_date,current_date),p_period_key,coalesce(nullif(trim(p_period_label),''),p_period_key),p_period_start,p_period_end,v_reviewer,null,p_status,nullif(trim(p_actual_progress),''),nullif(trim(p_achievements),''),nullif(trim(p_blockers),''),nullif(trim(p_evidence),''),nullif(trim(p_support_required),''),nullif(trim(p_next_actions),'')) returning id into v_checkin;
 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   if not exists(select 1 from hrc_hr_performance_plan_items where id=v_item and tenant_id=p_tenant and review_id=p_review) then raise exception 'Invalid performance measure in check-in'; end if;
   insert into hrc_hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source)
   values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),'manager_observation'));
  end if;
 end loop;
 perform unimis.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter (where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter (where system_score is not null)/sum(weight) filter (where system_score is not null),2) end
 into v_progress from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 update hrc_hr_performance_checkins set progress_percent=v_progress where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label);
end $$;
grant execute on function unimis.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;


-- SOURCE 202610251210_011j_pms_measurement_evidence_framework.sql
-- 011j: evidence-led PMS measurement framework.
alter table unimis.hrc_hr_performance_metric_library
 add column if not exists measurement_type text not null default 'numeric',
 add column if not exists data_source text not null default 'manager_verified',
 add column if not exists measurement_method text,
 add column if not exists evidence_required boolean not null default true,
 add column if not exists evidence_min_count integer not null default 1,
 add column if not exists rubric jsonb not null default '[]'::jsonb,
 add column if not exists checklist jsonb not null default '[]'::jsonb;

do $$ begin
 if not exists(select 1 from pg_constraint where conname='hr_perf_metric_measurement_type_check') then
  alter table unimis.hrc_hr_performance_metric_library add constraint hr_perf_metric_measurement_type_check check(measurement_type in ('system_calculated','formula','numeric','milestone','behavioral_rubric','compliance_checklist','development'));
 end if;
end $$;

create table if not exists unimis.hrc_hr_performance_evidence_attachments(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 review_id uuid not null references unimis.hrc_hr_performance_reviews(id) on delete cascade,
 plan_item_id uuid references unimis.hrc_hr_performance_plan_items(id) on delete cascade,
 checkin_id uuid references unimis.hrc_hr_performance_checkins(id) on delete cascade,
 file_name text not null, storage_path text not null, mime_type text, file_size bigint,
 description text, verification_status text not null default 'pending' check(verification_status in ('pending','verified','rejected')),
 verified_by uuid, verified_at timestamptz, uploaded_by uuid default auth.uid(), created_at timestamptz not null default now()
);
alter table unimis.hrc_hr_performance_evidence_attachments enable row level security;
drop policy if exists tenant_member_all on unimis.hrc_hr_performance_evidence_attachments;
create policy tenant_member_all on unimis.hrc_hr_performance_evidence_attachments for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('performance-evidence','performance-evidence',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf','text/plain','text/csv','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict(id) do update set file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists performance_evidence_member_insert on storage.objects;
create policy performance_evidence_member_insert on storage.objects for insert to authenticated with check(bucket_id='performance-evidence' and unimis.is_tenant_member((storage.foldername(name))[1]::uuid));
drop policy if exists performance_evidence_member_select on storage.objects;
create policy performance_evidence_member_select on storage.objects for select to authenticated using(bucket_id='performance-evidence' and unimis.is_tenant_member((storage.foldername(name))[1]::uuid));
drop policy if exists performance_evidence_member_delete on storage.objects;
create policy performance_evidence_member_delete on storage.objects for delete to authenticated using(bucket_id='performance-evidence' and unimis.is_tenant_member((storage.foldername(name))[1]::uuid));

-- System attendance result: percentage of attendance records that are present/late/half-day/on approved leave.
create or replace function unimis.hr_performance_attendance_result(p_tenant uuid,p_employee uuid,p_start date,p_end date) returns numeric
language plpgsql security definer set search_path=unimis as $$
declare total_count integer; acceptable integer;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select count(*),count(*) filter(where status in ('present','late','half_day','on_leave','holiday','off_day')) into total_count,acceptable
 from unimis.hrc_hr_attendance_records where tenant_id=p_tenant and employee_id=p_employee and work_date between p_start and p_end;
 if total_count=0 then return null; end if;
 return round(acceptable::numeric*100/total_count,2);
end $$;
grant execute on function unimis.hr_performance_attendance_result(uuid,uuid,date,date) to authenticated;

-- Mark the standard attendance KPI as system-calculated where it exists.
update unimis.hrc_hr_performance_metric_library set measurement_type='system_calculated',data_source='attendance_module',measurement_method='Calculated from HRPayrollCore attendance records for the selected review period.',evidence_required=false,evidence_min_count=0
where lower(name) like '%attendance%punctuality%';
update unimis.hrc_hr_performance_metric_library set measurement_type='behavioral_rubric',data_source='manager_verified',unit='score',measurement_method='Select the behaviourally anchored statement best supported by documented observations/evidence.',rubric='[{"score":1,"label":"Unsatisfactory","anchor":"Serious or persistent breaches of expected professional or ethical standards."},{"score":2,"label":"Needs improvement","anchor":"Repeated concerns requiring management intervention or coaching."},{"score":3,"label":"Meets expectations","anchor":"Generally professional, ethical and compliant; minor issues are corrected promptly."},{"score":4,"label":"Exceeds expectations","anchor":"Consistently professional, ethical and dependable with little or no corrective intervention."},{"score":5,"label":"Exceptional","anchor":"Consistently models integrity and professional conduct and positively influences others."}]'::jsonb,evidence_required=true,evidence_min_count=1
where lower(name) like '%professional conduct%ethic%';


-- SOURCE 202610251230_011k_objective_measurement_templates.sql
-- 011k: objective measurement templates, frozen activated-plan definitions, and check-in input audit trail.
alter table unimis.hrc_hr_performance_metric_library
 add column if not exists formula_config jsonb not null default '{}'::jsonb;

alter table unimis.hrc_hr_performance_plan_items
 add column if not exists measurement_type_snapshot text,
 add column if not exists data_source_snapshot text,
 add column if not exists measurement_method_snapshot text,
 add column if not exists rubric_snapshot jsonb,
 add column if not exists checklist_snapshot jsonb,
 add column if not exists formula_config_snapshot jsonb,
 add column if not exists evidence_required_snapshot boolean,
 add column if not exists evidence_min_count_snapshot integer;

alter table unimis.hrc_hr_performance_checkin_items
 add column if not exists measurement_inputs jsonb not null default '{}'::jsonb,
 add column if not exists measurement_type text;

-- Starter objective definitions. Administrators remain free to edit these in KPI Library before future plans are activated.
update unimis.hrc_hr_performance_metric_library
set measurement_type='formula',data_source='operational_record',unit='percent',
 measurement_method='Accuracy % = acceptable/correct work items divided by total work items reviewed × 100. Use a QA, inspection, transaction or rework record as evidence.',
 formula_config='{"numerator_label":"Acceptable / correct work items","denominator_label":"Total work items reviewed"}'::jsonb,
 evidence_required=true,evidence_min_count=1
where lower(name) like '%operational work quality%accuracy%';

update unimis.hrc_hr_performance_metric_library
set measurement_type='behavioral_rubric',data_source='manager_verified',unit='score',
 measurement_method='Select the teamwork/collaboration behaviour best supported by documented observations and evidence.',
 rubric='[{"score":1,"label":"Unsatisfactory","anchor":"Frequently undermines teamwork, communication or accountability and requires repeated intervention."},{"score":2,"label":"Needs improvement","anchor":"Inconsistent collaboration or communication causes avoidable friction or follow-up."},{"score":3,"label":"Meets expectations","anchor":"Works cooperatively, communicates appropriately and accepts normal accountability."},{"score":4,"label":"Exceeds expectations","anchor":"Consistently collaborates well, communicates proactively and supports team delivery."},{"score":5,"label":"Exceptional","anchor":"Models outstanding collaboration, resolves issues constructively and materially improves team effectiveness."}]'::jsonb,
 evidence_required=true,evidence_min_count=1
where lower(name) like '%operational collaboration%conduct%';

update unimis.hrc_hr_performance_metric_library
set measurement_type='compliance_checklist',data_source='manager_verified',unit='percent',
 measurement_method='Assess applicable SOP/control requirements as Compliant, Partially compliant, Non-compliant or N/A. The system calculates the percentage from applicable items.',
 checklist='[{"label":"Follows documented SOP steps for assigned work"},{"label":"Completes required records/documentation"},{"label":"Observes approval and control requirements"},{"label":"Escalates exceptions or deviations appropriately"},{"label":"Closes corrective actions within agreed timelines"}]'::jsonb,
 evidence_required=true,evidence_min_count=1
where lower(name) like '%responsibility%sop%execution%';

update unimis.hrc_hr_performance_metric_library
set measurement_type='formula',data_source='operational_record',unit='percent',
 measurement_method='Achievement % = completed/achieved agreed outputs divided by total agreed outputs due for the review period × 100. The underlying deliverables must be evidenced.',
 formula_config='{"numerator_label":"Outputs / milestones achieved","denominator_label":"Outputs / milestones due"}'::jsonb,
 evidence_required=true,evidence_min_count=1
where lower(name) like '%target%output%achievement%';

-- Freeze measurement definitions into every currently activated plan after the corrected starter definitions above.
update unimis.hrc_hr_performance_plan_items pi set
 measurement_type_snapshot=m.measurement_type,
 data_source_snapshot=m.data_source,
 measurement_method_snapshot=m.measurement_method,
 rubric_snapshot=m.rubric,
 checklist_snapshot=m.checklist,
 formula_config_snapshot=m.formula_config,
 evidence_required_snapshot=m.evidence_required,
 evidence_min_count_snapshot=m.evidence_min_count
from unimis.hrc_hr_performance_metric_library m, unimis.hrc_hr_performance_reviews r
where pi.metric_id=m.id and pi.review_id=r.id and r.plan_status='activated';

create or replace function unimis.hr_snapshot_performance_measurements_on_activation() returns trigger
language plpgsql security definer set search_path=unimis as $$
begin
 if new.plan_status='activated' and coalesce(old.plan_status,'')<>'activated' then
  update unimis.hrc_hr_performance_plan_items pi set
   measurement_type_snapshot=m.measurement_type,
   data_source_snapshot=m.data_source,
   measurement_method_snapshot=m.measurement_method,
   rubric_snapshot=m.rubric,
   checklist_snapshot=m.checklist,
   formula_config_snapshot=m.formula_config,
   evidence_required_snapshot=m.evidence_required,
   evidence_min_count_snapshot=m.evidence_min_count
  from unimis.hrc_hr_performance_metric_library m
  where pi.review_id=new.id and pi.tenant_id=new.tenant_id and pi.metric_id=m.id;
 end if;
 return new;
end $$;
drop trigger if exists trg_hr_snapshot_performance_measurements_on_activation on unimis.hrc_hr_performance_reviews;
create trigger trg_hr_snapshot_performance_measurements_on_activation after update of plan_status on unimis.hrc_hr_performance_reviews for each row execute function unimis.hr_snapshot_performance_measurements_on_activation();

create or replace function unimis.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare v_checkin uuid; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid; v_type text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select reviewer_employee_id into v_reviewer from hrc_hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and coalesce(finalization_status,'draft')<>'finalized';
 if not found then raise exception 'Review must be activated and not finalized'; end if;
 if coalesce(trim(p_period_key),'')='' then raise exception 'Check-in period is required'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'Check-in period end date cannot be before its start date'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 insert into hrc_hr_performance_checkins(tenant_id,review_id,checkin_date,period_key,period_label,period_start,period_end,reviewer_employee_id,progress_percent,status,actual_progress,achievements,blockers,evidence,support_required,next_actions)
 values(p_tenant,p_review,coalesce(p_checkin_date,current_date),p_period_key,coalesce(nullif(trim(p_period_label),''),p_period_key),p_period_start,p_period_end,v_reviewer,null,p_status,nullif(trim(p_actual_progress),''),nullif(trim(p_achievements),''),nullif(trim(p_blockers),''),nullif(trim(p_evidence),''),nullif(trim(p_support_required),''),nullif(trim(p_next_actions),'')) returning id into v_checkin;
 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   select coalesce(pi.measurement_type_snapshot,ml.measurement_type,'numeric') into v_type
   from hrc_hr_performance_plan_items pi left join hrc_hr_performance_metric_library ml on ml.id=pi.metric_id
   where pi.id=v_item and pi.tenant_id=p_tenant and pi.review_id=p_review;
   if not found then raise exception 'Invalid performance measure in check-in'; end if;
   insert into hrc_hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source,measurement_inputs,measurement_type)
   values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),'manager_observation'),coalesce(m->'measurement_inputs','{}'::jsonb),v_type);
  end if;
 end loop;
 perform unimis.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter (where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter (where system_score is not null)/sum(weight) filter (where system_score is not null),2) end
 into v_progress from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 update hrc_hr_performance_checkins set progress_percent=v_progress where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label);
end $$;
grant execute on function unimis.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;


-- SOURCE 202610260800_011l_evidence_verification_gate.sql
-- 011l: evidence verification gate for objective/manual PMS results.
alter table unimis.hrc_hr_performance_checkin_items
 add column if not exists verification_status text not null default 'pending',
 add column if not exists verified_by uuid,
 add column if not exists verified_at timestamptz,
 add column if not exists verification_note text;

do $$ begin
 if not exists(select 1 from pg_constraint where conname='hr_perf_checkin_item_verification_status_check') then
  alter table unimis.hrc_hr_performance_checkin_items add constraint hr_perf_checkin_item_verification_status_check
   check(verification_status in ('pending','verified','rejected','system_verified','manager_attested'));
 end if;
end $$;

-- Existing historical entries predate this gate; preserve them as verified legacy evidence.
update unimis.hrc_hr_performance_checkin_items set verification_status='verified'
where verification_status='pending' and created_at < now() - interval '1 minute';

create or replace function unimis.hr_verify_performance_evidence_submission(p_tenant uuid,p_checkin_item uuid,p_status text,p_note text default null) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare v_review uuid; v_item uuid;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_status not in ('verified','rejected') then raise exception 'Verification status must be verified or rejected'; end if;
 if p_status='rejected' and coalesce(trim(p_note),'')='' then raise exception 'A rejection reason is required'; end if;
 update hrc_hr_performance_checkin_items set verification_status=p_status,verified_by=auth.uid(),verified_at=now(),verification_note=nullif(trim(p_note),'')
 where tenant_id=p_tenant and id=p_checkin_item and verification_status='pending'
 returning review_id,plan_item_id into v_review,v_item;
 if not found then raise exception 'Pending evidence submission was not found'; end if;
 update hrc_hr_performance_evidence_attachments set verification_status=p_status,verified_by=auth.uid(),verified_at=now()
 where tenant_id=p_tenant and review_id=v_review and plan_item_id=v_item and verification_status='pending';
 perform unimis.hr_performance_refresh_intelligence(p_tenant,v_review);
 return jsonb_build_object('status',p_status,'review_id',v_review,'plan_item_id',v_item);
end $$;
grant execute on function unimis.hr_verify_performance_evidence_submission(uuid,uuid,text,text) to authenticated;

create or replace function unimis.hr_performance_refresh_intelligence(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare v_progress numeric(6,2); v_weight numeric(8,2); v_scored integer;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if exists(select 1 from hrc_hr_performance_reviews where tenant_id=p_tenant and id=p_review and finalization_status='finalized') then raise exception 'Finalized appraisal is locked'; end if;

 -- Only verified/system-verified/manager-attested results may become the authoritative actual.
 with latest as (
  select distinct on (plan_item_id) plan_item_id,actual_value,evidence_source
  from hrc_hr_performance_checkin_items
  where tenant_id=p_tenant and review_id=p_review and verification_status in ('verified','system_verified','manager_attested')
  order by plan_item_id,created_at desc,id desc
 ), counts as (
  select plan_item_id,count(*)::int evidence_count from hrc_hr_performance_checkin_items
  where tenant_id=p_tenant and review_id=p_review and verification_status in ('verified','system_verified','manager_attested') group by plan_item_id
 )
 update hrc_hr_performance_plan_items p set
  actual_value=l.actual_value,
  latest_evidence_source=l.evidence_source,
  evidence_count=coalesce(c.evidence_count,0)
 from latest l left join counts c on c.plan_item_id=l.plan_item_id
 where p.tenant_id=p_tenant and p.review_id=p_review and p.id=l.plan_item_id;

 -- If an item has submissions but none accepted, do not let pending/rejected facts become a score.
 update hrc_hr_performance_plan_items p set actual_value=null,system_score=null,evidence_count=0
 where p.tenant_id=p_tenant and p.review_id=p_review
 and exists(select 1 from hrc_hr_performance_checkin_items ci where ci.tenant_id=p_tenant and ci.review_id=p_review and ci.plan_item_id=p.id)
 and not exists(select 1 from hrc_hr_performance_checkin_items ci where ci.tenant_id=p_tenant and ci.review_id=p_review and ci.plan_item_id=p.id and ci.verification_status in ('verified','system_verified','manager_attested'));

 update hrc_hr_performance_plan_items set
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
 into v_weight,v_progress from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 return jsonb_build_object('items_scored',v_scored,'progress_percent',v_progress,'plan_weight',v_weight);
end $$;
grant execute on function unimis.hr_performance_refresh_intelligence(uuid,uuid) to authenticated;

create or replace function unimis.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare v_checkin uuid; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid; v_type text; v_source text; v_verification text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select reviewer_employee_id into v_reviewer from hrc_hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and coalesce(finalization_status,'draft')<>'finalized';
 if not found then raise exception 'Review must be activated and not finalized'; end if;
 if coalesce(trim(p_period_key),'')='' then raise exception 'Check-in period is required'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'Check-in period end date cannot be before its start date'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 insert into hrc_hr_performance_checkins(tenant_id,review_id,checkin_date,period_key,period_label,period_start,period_end,reviewer_employee_id,progress_percent,status,actual_progress,achievements,blockers,evidence,support_required,next_actions)
 values(p_tenant,p_review,coalesce(p_checkin_date,current_date),p_period_key,coalesce(nullif(trim(p_period_label),''),p_period_key),p_period_start,p_period_end,v_reviewer,null,p_status,nullif(trim(p_actual_progress),''),nullif(trim(p_achievements),''),nullif(trim(p_blockers),''),nullif(trim(p_evidence),''),nullif(trim(p_support_required),''),nullif(trim(p_next_actions),'')) returning id into v_checkin;
 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   select coalesce(pi.measurement_type_snapshot,ml.measurement_type,'numeric'),coalesce(pi.data_source_snapshot,ml.data_source,'manager_verified') into v_type,v_source
   from hrc_hr_performance_plan_items pi left join hrc_hr_performance_metric_library ml on ml.id=pi.metric_id
   where pi.id=v_item and pi.tenant_id=p_tenant and pi.review_id=p_review;
   if not found then raise exception 'Invalid performance measure in check-in'; end if;
   v_verification=case when v_type='system_calculated' then 'system_verified' when v_type='behavioral_rubric' then 'manager_attested' else 'pending' end;
   if v_verification='pending' and coalesce(trim(m->>'evidence'),'')='' and not exists(select 1 from hrc_hr_performance_evidence_attachments a where a.tenant_id=p_tenant and a.review_id=p_review and a.plan_item_id=v_item) then
    raise exception 'Objective/manual source figures require evidence before submission';
   end if;
   insert into hrc_hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source,measurement_inputs,measurement_type,verification_status)
   values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),coalesce(m->'measurement_inputs','{}'::jsonb),v_type,v_verification);
  end if;
 end loop;
 perform unimis.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter(where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter(where system_score is not null)/sum(weight) filter(where system_score is not null),2) end into v_progress from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 update hrc_hr_performance_checkins set progress_percent=v_progress where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label,'verification_required',true);
end $$;
grant execute on function unimis.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;


-- SOURCE 202610260830_011m_checkin_verified_progress.sql
-- 011m: preserve recorded check-in progress while separately tracking the
-- current verified weighted contribution for that exact check-in.
alter table unimis.hrc_hr_performance_checkins
 add column if not exists recorded_progress_percent numeric(6,2),
 add column if not exists current_verified_progress_percent numeric(6,2),
 add column if not exists verified_measure_count integer not null default 0,
 add column if not exists total_measure_count integer not null default 0,
 add column if not exists verification_progress_updated_at timestamptz;

create or replace function unimis.hr_refresh_checkin_verified_progress(p_tenant uuid,p_checkin uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare v_review uuid; v_progress numeric(6,2); v_verified integer; v_total integer;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select review_id into v_review from hrc_hr_performance_checkins where tenant_id=p_tenant and id=p_checkin;
 if not found then raise exception 'Check-in not found'; end if;
 select count(*) into v_total from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=v_review;
 with accepted as (
  select distinct on (ci.plan_item_id) ci.plan_item_id,ci.actual_value
  from hrc_hr_performance_checkin_items ci
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
  from accepted a join hrc_hr_performance_plan_items p on p.id=a.plan_item_id
  where p.tenant_id=p_tenant and p.review_id=v_review
 )
 select count(*) filter(where score is not null)::int,
        round(coalesce(sum(score*weight/100.0) filter(where score is not null),0),2)
 into v_verified,v_progress from scored;
 update hrc_hr_performance_checkins set current_verified_progress_percent=v_progress,
  verified_measure_count=coalesce(v_verified,0),total_measure_count=v_total,
  verification_progress_updated_at=now()
 where tenant_id=p_tenant and id=p_checkin;
 return jsonb_build_object('checkin_id',p_checkin,'current_verified_progress_percent',v_progress,'verified_measure_count',coalesce(v_verified,0),'total_measure_count',v_total);
end $$;
grant execute on function unimis.hr_refresh_checkin_verified_progress(uuid,uuid) to authenticated;

-- Wrap verification so the affected historical check-in is refreshed after the
-- evidence gate changes status. Review-level intelligence remains unchanged.
create or replace function unimis.hr_verify_performance_evidence_submission(p_tenant uuid,p_checkin_item uuid,p_status text,p_note text default null) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare v_review uuid; v_item uuid; v_checkin uuid; v_progress jsonb;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_status not in ('verified','rejected') then raise exception 'Verification status must be verified or rejected'; end if;
 if p_status='rejected' and coalesce(trim(p_note),'')='' then raise exception 'A rejection reason is required'; end if;
 update hrc_hr_performance_checkin_items set verification_status=p_status,verified_by=auth.uid(),verified_at=now(),verification_note=nullif(trim(p_note),'')
 where tenant_id=p_tenant and id=p_checkin_item and verification_status='pending'
 returning review_id,plan_item_id,checkin_id into v_review,v_item,v_checkin;
 if not found then raise exception 'Pending evidence submission was not found'; end if;
 update hrc_hr_performance_evidence_attachments set verification_status=p_status,verified_by=auth.uid(),verified_at=now()
 where tenant_id=p_tenant and review_id=v_review and plan_item_id=v_item and verification_status='pending';
 perform unimis.hr_performance_refresh_intelligence(p_tenant,v_review);
 v_progress:=unimis.hr_refresh_checkin_verified_progress(p_tenant,v_checkin);
 return jsonb_build_object('status',p_status,'review_id',v_review,'plan_item_id',v_item,'checkin_id',v_checkin,'checkin_progress',v_progress);
end $$;
grant execute on function unimis.hr_verify_performance_evidence_submission(uuid,uuid,text,text) to authenticated;

-- Backfill existing check-ins without depending on session membership during migration.
with totals as (
 select tenant_id,review_id,count(*)::int total_count from unimis.hrc_hr_performance_plan_items group by tenant_id,review_id
), accepted as (
 select distinct on (ci.checkin_id,ci.plan_item_id) ci.tenant_id,ci.checkin_id,ci.review_id,ci.plan_item_id,ci.actual_value
 from unimis.hrc_hr_performance_checkin_items ci
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
 from accepted a join unimis.hrc_hr_performance_plan_items p on p.id=a.plan_item_id and p.tenant_id=a.tenant_id
), agg as (
 select tenant_id,checkin_id,review_id,count(*) filter(where score is not null)::int verified_count,
  round(coalesce(sum(score*weight/100.0) filter(where score is not null),0),2) current_progress
 from scored group by tenant_id,checkin_id,review_id
)
update unimis.hrc_hr_performance_checkins c set
 current_verified_progress_percent=coalesce(a.current_progress,0),
 verified_measure_count=coalesce(a.verified_count,0),
 total_measure_count=coalesce(t.total_count,0),verification_progress_updated_at=now()
from totals t left join agg a on a.tenant_id=t.tenant_id and a.review_id=t.review_id and a.checkin_id is not null
where c.tenant_id=t.tenant_id and c.review_id=t.review_id and (a.checkin_id=c.id or a.checkin_id is null);

-- Preserve the old progress snapshot as "recorded" where one exists. New rows
-- will receive a snapshot in the application/database flow below.
update unimis.hrc_hr_performance_checkins
set recorded_progress_percent=progress_percent
where recorded_progress_percent is null and progress_percent is not null;


create or replace function unimis.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare v_checkin uuid; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid; v_type text; v_source text; v_verification text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select reviewer_employee_id into v_reviewer from hrc_hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and coalesce(finalization_status,'draft')<>'finalized';
 if not found then raise exception 'Review must be activated and not finalized'; end if;
 if coalesce(trim(p_period_key),'')='' then raise exception 'Check-in period is required'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'Check-in period end date cannot be before its start date'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 insert into hrc_hr_performance_checkins(tenant_id,review_id,checkin_date,period_key,period_label,period_start,period_end,reviewer_employee_id,progress_percent,status,actual_progress,achievements,blockers,evidence,support_required,next_actions)
 values(p_tenant,p_review,coalesce(p_checkin_date,current_date),p_period_key,coalesce(nullif(trim(p_period_label),''),p_period_key),p_period_start,p_period_end,v_reviewer,null,p_status,nullif(trim(p_actual_progress),''),nullif(trim(p_achievements),''),nullif(trim(p_blockers),''),nullif(trim(p_evidence),''),nullif(trim(p_support_required),''),nullif(trim(p_next_actions),'')) returning id into v_checkin;
 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   select coalesce(pi.measurement_type_snapshot,ml.measurement_type,'numeric'),coalesce(pi.data_source_snapshot,ml.data_source,'manager_verified') into v_type,v_source
   from hrc_hr_performance_plan_items pi left join hrc_hr_performance_metric_library ml on ml.id=pi.metric_id
   where pi.id=v_item and pi.tenant_id=p_tenant and pi.review_id=p_review;
   if not found then raise exception 'Invalid performance measure in check-in'; end if;
   v_verification=case when v_type='system_calculated' then 'system_verified' when v_type='behavioral_rubric' then 'manager_attested' else 'pending' end;
   if v_verification='pending' and coalesce(trim(m->>'evidence'),'')='' and not exists(select 1 from hrc_hr_performance_evidence_attachments a where a.tenant_id=p_tenant and a.review_id=p_review and a.plan_item_id=v_item) then
    raise exception 'Objective/manual source figures require evidence before submission';
   end if;
   insert into hrc_hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source,measurement_inputs,measurement_type,verification_status)
   values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),coalesce(m->'measurement_inputs','{}'::jsonb),v_type,v_verification);
  end if;
 end loop;
 perform unimis.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter(where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter(where system_score is not null)/sum(weight) filter(where system_score is not null),2) end into v_progress from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 perform unimis.hr_refresh_checkin_verified_progress(p_tenant,v_checkin);
 update hrc_hr_performance_checkins set progress_percent=current_verified_progress_percent, recorded_progress_percent=current_verified_progress_percent where id=v_checkin;
 select current_verified_progress_percent into v_progress from hrc_hr_performance_checkins where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label,'verification_required',true);
end $$;
grant execute on function unimis.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;


-- SOURCE 202610260845_011n_checkin_evidence_linkage_repair.sql
-- 011n: repair legacy check-in/evidence linkage and refresh historical verification progress.
-- Future submissions already carry checkin_id; this repair is deliberately conservative:
-- legacy/mismatched rows are reassigned only when the review has exactly one check-in.

with single_checkin_reviews as (
  select tenant_id, review_id, min(id::text)::uuid as checkin_id
  from unimis.hrc_hr_performance_checkins
  group by tenant_id, review_id
  having count(*) = 1
)
update unimis.hrc_hr_performance_checkin_items ci
set checkin_id = s.checkin_id
from single_checkin_reviews s
where ci.tenant_id = s.tenant_id
  and ci.review_id = s.review_id
  and ci.checkin_id is distinct from s.checkin_id;

-- Recalculate every historical check-in strictly from submissions linked to that check-in.
with totals as (
  select tenant_id, review_id, count(*)::int as total_count
  from unimis.hrc_hr_performance_plan_items
  group by tenant_id, review_id
), accepted as (
  select distinct on (ci.tenant_id, ci.checkin_id, ci.plan_item_id)
         ci.tenant_id, ci.checkin_id, ci.review_id, ci.plan_item_id, ci.actual_value
  from unimis.hrc_hr_performance_checkin_items ci
  where ci.checkin_id is not null
    and ci.verification_status in ('verified','system_verified','manager_attested')
  order by ci.tenant_id, ci.checkin_id, ci.plan_item_id, ci.created_at desc, ci.id desc
), scored as (
  select a.tenant_id, a.checkin_id, a.review_id, p.weight,
         case
           when a.actual_value is null or p.target_value is null then null
           when p.direction='higher_better' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
           when p.direction='lower_better' and a.actual_value=0 then 100
           when p.direction='lower_better' and a.actual_value<>0 then least(100,(p.target_value/a.actual_value)*100)
           when p.direction='pass_fail' then case when a.actual_value>=p.target_value then 100 else 0 end
           when p.direction='milestone' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
           else null
         end as score
  from accepted a
  join unimis.hrc_hr_performance_plan_items p
    on p.tenant_id=a.tenant_id and p.review_id=a.review_id and p.id=a.plan_item_id
), agg as (
  select tenant_id, checkin_id, review_id,
         count(*) filter (where score is not null)::int as verified_count,
         round(coalesce(sum(score*weight/100.0) filter (where score is not null),0),2) as current_progress
  from scored
  group by tenant_id, checkin_id, review_id
)
update unimis.hrc_hr_performance_checkins c
set current_verified_progress_percent = coalesce(a.current_progress,0),
    verified_measure_count = coalesce(a.verified_count,0),
    total_measure_count = coalesce(t.total_count,0),
    verification_progress_updated_at = now()
from totals t
left join agg a
  on a.tenant_id=t.tenant_id and a.review_id=t.review_id
where c.tenant_id=t.tenant_id
  and c.review_id=t.review_id
  and (a.checkin_id=c.id or not exists (
        select 1 from agg ax
        where ax.tenant_id=c.tenant_id and ax.review_id=c.review_id and ax.checkin_id=c.id
      ));

-- Keep the runtime refresh function exact-check-in scoped.
create or replace function unimis.hr_refresh_checkin_verified_progress(p_tenant uuid,p_checkin uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare v_review uuid; v_progress numeric(6,2); v_verified integer; v_total integer;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select review_id into v_review from hrc_hr_performance_checkins where tenant_id=p_tenant and id=p_checkin;
 if not found then raise exception 'Check-in not found'; end if;
 select count(*) into v_total from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=v_review;
 with accepted as (
  select distinct on (ci.plan_item_id) ci.plan_item_id,ci.actual_value
  from hrc_hr_performance_checkin_items ci
  where ci.tenant_id=p_tenant and ci.review_id=v_review and ci.checkin_id=p_checkin
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
  from accepted a join hrc_hr_performance_plan_items p on p.id=a.plan_item_id
  where p.tenant_id=p_tenant and p.review_id=v_review
 )
 select count(*) filter(where score is not null)::int,
        round(coalesce(sum(score*weight/100.0) filter(where score is not null),0),2)
 into v_verified,v_progress from scored;
 update hrc_hr_performance_checkins set current_verified_progress_percent=v_progress,
  verified_measure_count=coalesce(v_verified,0),total_measure_count=v_total,
  verification_progress_updated_at=now()
 where tenant_id=p_tenant and id=p_checkin;
 return jsonb_build_object('checkin_id',p_checkin,'current_verified_progress_percent',v_progress,'verified_measure_count',coalesce(v_verified,0),'total_measure_count',v_total);
end $$;
grant execute on function unimis.hr_refresh_checkin_verified_progress(uuid,uuid) to authenticated;


-- SOURCE 202610260900_011o_checkin_verified_progress_exact_refresh.sql
﻿-- 011o: exact check-in verification refresh with safe single-check-in fallback.
-- Repairs the current legacy test without allowing evidence to leak between periods.

create or replace function unimis.hr_refresh_checkin_verified_progress(p_tenant uuid,p_checkin uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare v_review uuid; v_progress numeric(6,2); v_verified integer; v_total integer; v_checkin_count integer;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select review_id into v_review from hrc_hr_performance_checkins where tenant_id=p_tenant and id=p_checkin;
 if not found then raise exception 'Check-in not found'; end if;
 select count(*) into v_total from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=v_review;
 select count(*) into v_checkin_count from hrc_hr_performance_checkins where tenant_id=p_tenant and review_id=v_review;
 with accepted as (
  select distinct on (ci.plan_item_id) ci.plan_item_id,ci.actual_value
  from hrc_hr_performance_checkin_items ci
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
  from accepted a join hrc_hr_performance_plan_items p on p.id=a.plan_item_id
  where p.tenant_id=p_tenant and p.review_id=v_review
 )
 select count(*) filter(where score is not null)::int,
        round(coalesce(sum(score*weight/100.0) filter(where score is not null),0),2)
 into v_verified,v_progress from scored;
 update hrc_hr_performance_checkins set current_verified_progress_percent=v_progress,
  verified_measure_count=coalesce(v_verified,0),total_measure_count=v_total,
  verification_progress_updated_at=now()
 where tenant_id=p_tenant and id=p_checkin;
 -- Permanently repair orphan/mismatched legacy submissions only when this review has one check-in.
 if v_checkin_count=1 then
  update hrc_hr_performance_checkin_items set checkin_id=p_checkin
  where tenant_id=p_tenant and review_id=v_review and checkin_id is distinct from p_checkin;
 end if;
 return jsonb_build_object('checkin_id',p_checkin,'current_verified_progress_percent',v_progress,'verified_measure_count',coalesce(v_verified,0),'total_measure_count',v_total);
end $$;
grant execute on function unimis.hr_refresh_checkin_verified_progress(uuid,uuid) to authenticated;

create or replace function unimis.hr_verify_performance_evidence_submission(p_tenant uuid,p_checkin_item uuid,p_status text,p_note text default null) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare v_review uuid; v_item uuid; v_checkin uuid; v_count integer;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_status not in ('verified','rejected') then raise exception 'Verification status must be verified or rejected'; end if;
 if p_status='rejected' and coalesce(trim(p_note),'')='' then raise exception 'A rejection reason is required'; end if;
 update hrc_hr_performance_checkin_items set verification_status=p_status,verified_by=auth.uid(),verified_at=now(),verification_note=nullif(trim(p_note),'')
 where tenant_id=p_tenant and id=p_checkin_item and verification_status='pending'
 returning review_id,plan_item_id,checkin_id into v_review,v_item,v_checkin;
 if not found then raise exception 'Pending evidence submission was not found'; end if;
 update hrc_hr_performance_evidence_attachments set verification_status=p_status,verified_by=auth.uid(),verified_at=now()
 where tenant_id=p_tenant and review_id=v_review and plan_item_id=v_item and verification_status='pending';
 perform unimis.hr_performance_refresh_intelligence(p_tenant,v_review);
 if v_checkin is null then
  select count(*), min(id::text)::uuid into v_count,v_checkin from hrc_hr_performance_checkins where tenant_id=p_tenant and review_id=v_review;
  if v_count<>1 then v_checkin=null; end if;
 end if;
 if v_checkin is not null then perform unimis.hr_refresh_checkin_verified_progress(p_tenant,v_checkin); end if;
 return jsonb_build_object('status',p_status,'review_id',v_review,'plan_item_id',v_item,'checkin_id',v_checkin);
end $$;
grant execute on function unimis.hr_verify_performance_evidence_submission(uuid,uuid,text,text) to authenticated;



-- SOURCE 202610260915_011p_checkin_workspace_integrity.sql
-- 011p: prevent accidental duplicate scheduled-period check-ins and suppress legacy duplicate pending evidence.

create or replace function unimis.hr_guard_duplicate_performance_checkin_period() returns trigger
language plpgsql security definer set search_path=unimis as $$
begin
  if coalesce(new.period_key,'') <> '' and upper(new.period_key) <> 'ADHOC' and exists (
    select 1 from unimis.hrc_hr_performance_checkins c
    where c.tenant_id=new.tenant_id and c.review_id=new.review_id
      and c.period_key=new.period_key and c.id<>new.id
  ) then
    raise exception 'A check-in has already been recorded for this employee and review period. Open Check-in History instead of submitting the same period again.';
  end if;
  return new;
end $$;

drop trigger if exists trg_hr_guard_duplicate_performance_checkin_period on unimis.hrc_hr_performance_checkins;
create trigger trg_hr_guard_duplicate_performance_checkin_period
before insert or update of tenant_id,review_id,period_key on unimis.hrc_hr_performance_checkins
for each row execute function unimis.hr_guard_duplicate_performance_checkin_period();

-- Preserve audit rows but close exact pending duplicates where an identical result/reference is already verified.
update unimis.hrc_hr_performance_checkin_items p
set verification_status='rejected',
    verified_at=coalesce(p.verified_at,now()),
    verification_note=coalesce(p.verification_note,'Duplicate submission suppressed: an identical result and evidence reference is already verified.')
where p.verification_status='pending'
  and exists (
    select 1 from unimis.hrc_hr_performance_checkin_items v
    where v.tenant_id=p.tenant_id
      and v.review_id=p.review_id
      and v.plan_item_id=p.plan_item_id
      and v.id<>p.id
      and v.actual_value is not distinct from p.actual_value
      and coalesce(v.evidence,'')=coalesce(p.evidence,'')
      and v.verification_status in ('verified','system_verified','manager_attested')
  );


-- SOURCE 202610260930_011q_checkin_history_integrity.sql
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
             (select count(*) from unimis.hrc_hr_performance_checkin_items i where i.checkin_id=c.id) +
             (select count(*) from unimis.hrc_hr_performance_evidence_attachments a where a.checkin_id=c.id) as link_count
      from unimis.hrc_hr_performance_checkins c
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
    update unimis.hrc_hr_performance_checkin_items
       set checkin_id=r.keep_id
     where checkin_id=r.duplicate_id;

    update unimis.hrc_hr_performance_evidence_attachments
       set checkin_id=r.keep_id
     where checkin_id=r.duplicate_id;

    delete from unimis.hrc_hr_performance_checkins
     where id=r.duplicate_id;
  end loop;
end $$;

-- Database-level guarantee in addition to the friendly trigger message.
create unique index if not exists uq_hr_performance_checkins_scheduled_period
on unimis.hrc_hr_performance_checkins(tenant_id,review_id,period_key)
where coalesce(period_key,'')<>'' and upper(period_key)<>'ADHOC';


-- SOURCE 202610260940_011u_attendance_administration_historical_import.sql
-- 011u Attendance Administration & Historical Import
create table if not exists unimis.hrc_hr_attendance_change_audit(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 attendance_id uuid references unimis.hrc_hr_attendance_records(id) on delete set null, employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,
 work_date date not null, action text not null check(action in ('create','correct','import_create','import_correct')),
 reason text not null, old_record jsonb, new_record jsonb, changed_by uuid default auth.uid(), changed_at timestamptz not null default now()
);
alter table unimis.hrc_hr_attendance_change_audit enable row level security;
drop policy if exists attendance_change_audit_member_select on unimis.hrc_hr_attendance_change_audit;
create policy attendance_change_audit_member_select on unimis.hrc_hr_attendance_change_audit for select to authenticated using(unimis.is_tenant_member(tenant_id));
create index if not exists idx_attendance_change_audit_tenant_date on unimis.hrc_hr_attendance_change_audit(tenant_id,work_date desc);

create or replace function unimis.hr_admin_upsert_attendance(p_tenant uuid,p_employee uuid,p_work_date date,p_check_in timestamptz,p_check_out timestamptz,p_status text,p_site uuid,p_reason text,p_capture_method text default 'manual') returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare oldr unimis.hrc_hr_attendance_records%rowtype; newr unimis.hrc_hr_attendance_records%rowtype; act text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if coalesce(trim(p_reason),'')='' then raise exception 'Reason is required for manual attendance entry or correction'; end if;
 if p_capture_method not in ('manual','import') then raise exception 'Invalid administrative attendance source'; end if;
 if p_status not in ('present','absent','late','half_day','on_leave','holiday','off_day') then raise exception 'Invalid attendance status'; end if;
 if not exists(select 1 from unimis.hrc_hr_employees where tenant_id=p_tenant and id=p_employee) then raise exception 'Employee not found'; end if;
 select * into oldr from unimis.hrc_hr_attendance_records where tenant_id=p_tenant and employee_id=p_employee and work_date=p_work_date for update;
 if oldr.id is null then
  insert into unimis.hrc_hr_attendance_records(tenant_id,employee_id,work_date,check_in,check_out,status,capture_method,attendance_site_id,notes,correction_reason,approval_status,approved_by,approved_at)
  values(p_tenant,p_employee,p_work_date,p_check_in,p_check_out,p_status,p_capture_method,p_site,p_reason,p_reason,'approved',auth.uid(),now()) returning * into newr;
  act=case when p_capture_method='import' then 'import_create' else 'create' end;
 else
  update unimis.hrc_hr_attendance_records set check_in=p_check_in,check_out=p_check_out,status=p_status,capture_method=p_capture_method,attendance_site_id=p_site,notes=p_reason,correction_reason=p_reason,approval_status='approved',approved_by=auth.uid(),approved_at=now()
  where id=oldr.id returning * into newr;
  act=case when p_capture_method='import' then 'import_correct' else 'correct' end;
 end if;
 insert into unimis.hrc_hr_attendance_change_audit(tenant_id,attendance_id,employee_id,work_date,action,reason,old_record,new_record)
 values(p_tenant,newr.id,p_employee,p_work_date,act,p_reason,case when oldr.id is null then null else to_jsonb(oldr) end,to_jsonb(newr));
 return jsonb_build_object('ok',true,'attendance_id',newr.id,'action',act);
end $$;
grant execute on function unimis.hr_admin_upsert_attendance(uuid,uuid,date,timestamptz,timestamptz,text,uuid,text,text) to authenticated;




-- Refresh Supabase/PostgREST schema cache after this stage.
NOTIFY pgrst, 'reload schema';
