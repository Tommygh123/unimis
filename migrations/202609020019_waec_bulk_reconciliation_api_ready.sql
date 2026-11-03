create sequence if not exists public.waec_batch_number_seq start 1;
grant usage,select on sequence public.waec_batch_number_seq to authenticated;

create table if not exists public.waec_verification_batches(
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 batch_number text not null,
 admission_cycle_id uuid references public.admission_cycles(id) on delete set null,
 method text not null default 'waec_bulk' check(method in('waec_bulk','waec_api')),
 status text not null default 'draft' check(status in('draft','exported','submitted','returned','reconciled','closed','failed')),
 candidate_count integer not null default 0,matched_count integer not null default 0,exception_count integer not null default 0,
 exported_at timestamptz,submitted_at timestamptz,returned_at timestamptz,reconciled_at timestamptz,
 provider_reference text,notes text,created_by uuid,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(institution_id,batch_number)
);
create table if not exists public.waec_verification_batch_candidates(
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 batch_id uuid not null references public.waec_verification_batches(id) on delete cascade,
 application_id uuid not null references public.applications(id) on delete cascade,
 applicant_id uuid not null references public.applicants(id) on delete cascade,
 qualification_id uuid not null references public.applicant_qualifications(id) on delete cascade,
 index_number text,exam_year integer,exam_type text,applicant_name text,
 reconciliation_status text not null default 'pending' check(reconciliation_status in('pending','matched','grade_mismatch','identity_review','not_returned','invalid_result')),
 official_candidate_name text,official_result jsonb not null default '{}'::jsonb,comparison_result jsonb not null default '{}'::jsonb,notes text,reconciled_at timestamptz,created_at timestamptz not null default now(),
 unique(batch_id,qualification_id)
);
create index if not exists idx_waec_batch_candidates_batch_status on public.waec_verification_batch_candidates(batch_id,reconciliation_status);
create index if not exists idx_waec_batch_candidates_identity on public.waec_verification_batch_candidates(institution_id,index_number,exam_year);
alter table public.waec_verification_batches enable row level security;
alter table public.waec_verification_batch_candidates enable row level security;
grant select on public.waec_verification_batches,public.waec_verification_batch_candidates to authenticated;
revoke all on public.waec_verification_batches,public.waec_verification_batch_candidates from anon;

drop policy if exists "Institution members view WAEC batches" on public.waec_verification_batches;
create policy "Institution members view WAEC batches" on public.waec_verification_batches for select to authenticated using(exists(select 1 from public.institution_users iu where iu.user_id=auth.uid() and iu.institution_id=waec_verification_batches.institution_id and iu.status='active'));
drop policy if exists "Institution members view WAEC batch candidates" on public.waec_verification_batch_candidates;
create policy "Institution members view WAEC batch candidates" on public.waec_verification_batch_candidates for select to authenticated using(exists(select 1 from public.institution_users iu where iu.user_id=auth.uid() and iu.institution_id=waec_verification_batch_candidates.institution_id and iu.status='active'));

create or replace function public.unimis_create_waec_verification_batch(p_qualification_ids uuid[],p_admission_cycle_id uuid default null,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_inst uuid;v_batch public.waec_verification_batches;v_count integer:=0;
begin
 select iu.institution_id into v_inst from public.institution_users iu where iu.user_id=auth.uid() and iu.status='active' order by iu.is_primary desc nulls last limit 1;
 if v_inst is null then raise exception 'Institution membership required';end if;
 if coalesce(array_length(p_qualification_ids,1),0)=0 then raise exception 'Select at least one WAEC qualification';end if;
 insert into public.waec_verification_batches(institution_id,batch_number,admission_cycle_id,method,status,notes,created_by)
 values(v_inst,'WB-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('public.waec_batch_number_seq')::text,6,'0'),p_admission_cycle_id,'waec_bulk','draft',nullif(trim(p_notes),''),auth.uid()) returning * into v_batch;
 insert into public.waec_verification_batch_candidates(institution_id,batch_id,application_id,applicant_id,qualification_id,index_number,exam_year,exam_type,applicant_name)
 select distinct on(q.id) v_inst,v_batch.id,a.id,ap.id,q.id,q.index_number,q.completion_year,coalesce(q.exam_sitting,q.qualification_type,'WASSCE'),trim(concat_ws(' ',ap.first_name,ap.middle_name,ap.last_name))
 from public.applicant_qualifications q join public.applicants ap on ap.id=q.applicant_id and ap.institution_id=v_inst join public.applications a on a.applicant_id=ap.id and a.institution_id=v_inst
 where q.id=any(p_qualification_ids) and upper(coalesce(q.qualification_type,''))='WASSCE' and a.submitted_at is not null and lower(coalesce(a.payment_status,'')) in('paid','verified','not_required') and(p_admission_cycle_id is null or a.admission_cycle_id=p_admission_cycle_id)
 order by q.id,a.submitted_at desc on conflict(batch_id,qualification_id) do nothing;
 get diagnostics v_count=row_count;
 if v_count=0 then delete from public.waec_verification_batches where id=v_batch.id;raise exception 'None of the selected qualifications belongs to a paid and submitted application';end if;
 update public.waec_verification_batches set candidate_count=v_count where id=v_batch.id returning * into v_batch;
 return to_jsonb(v_batch);
end$$;
grant execute on function public.unimis_create_waec_verification_batch(uuid[],uuid,text) to authenticated;

create or replace function public.unimis_update_waec_batch_status(p_batch_id uuid,p_status text,p_provider_reference text default null,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_inst uuid;v_row public.waec_verification_batches;v_status text:=lower(p_status);
begin
 select iu.institution_id into v_inst from public.institution_users iu where iu.user_id=auth.uid() and iu.status='active' order by iu.is_primary desc nulls last limit 1;
 if v_inst is null then raise exception 'Institution membership required';end if;
 update public.waec_verification_batches set status=v_status,provider_reference=coalesce(nullif(trim(p_provider_reference),''),provider_reference),notes=coalesce(nullif(trim(p_notes),''),notes),exported_at=case when v_status='exported' then now() else exported_at end,submitted_at=case when v_status='submitted' then now() else submitted_at end,returned_at=case when v_status='returned' then now() else returned_at end,reconciled_at=case when v_status='reconciled' then now() else reconciled_at end,updated_at=now()
 where id=p_batch_id and institution_id=v_inst returning * into v_row;
 if v_row.id is null then raise exception 'WAEC batch not found';end if;return to_jsonb(v_row);
end$$;
grant execute on function public.unimis_update_waec_batch_status(uuid,text,text,text) to authenticated;

create or replace function public.unimis_reconcile_waec_bulk_batch(p_batch_id uuid,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_inst uuid;v_batch public.waec_verification_batches;v_row jsonb;v_candidate public.waec_verification_batch_candidates;v_subjects jsonb;v_cmp jsonb;v_entered integer;v_matches integer;v_name text;v_en text;v_on text;v_status text;v_processed integer:=0;v_matched integer:=0;v_exceptions integer:=0;
begin
 select iu.institution_id into v_inst from public.institution_users iu where iu.user_id=auth.uid() and iu.status='active' order by iu.is_primary desc nulls last limit 1;
 select * into v_batch from public.waec_verification_batches where id=p_batch_id and institution_id=v_inst;if v_batch.id is null then raise exception 'WAEC batch not found';end if;
 for v_row in select value from jsonb_array_elements(p_rows) loop
  v_candidate:=null;
  select * into v_candidate from public.waec_verification_batch_candidates c where c.batch_id=p_batch_id and regexp_replace(coalesce(c.index_number,''),'[^0-9A-Za-z]','','g')=regexp_replace(coalesce(v_row->>'index_number',''),'[^0-9A-Za-z]','','g') and coalesce(c.exam_year,0)=coalesce(nullif(v_row->>'exam_year','')::integer,0) limit 1;
  if v_candidate.id is null then continue;end if;v_processed:=v_processed+1;v_subjects:=coalesce(v_row->'subjects','[]'::jsonb);v_name:=nullif(trim(v_row->>'candidate_name'),'');v_en:=lower(regexp_replace(coalesce(v_candidate.applicant_name,''),'[^a-zA-Z0-9]','','g'));v_on:=lower(regexp_replace(coalesce(v_name,''),'[^a-zA-Z0-9]','','g'));
  select count(*) into v_entered from public.applicant_subject_results r where r.qualification_id=v_candidate.qualification_id;
  select count(*) into v_matches from public.applicant_subject_results r where r.qualification_id=v_candidate.qualification_id and exists(select 1 from jsonb_array_elements(v_subjects)s where lower(regexp_replace(coalesce(s->>'subject_name',''),'[^a-zA-Z0-9]','','g'))=lower(regexp_replace(coalesce(r.subject_name,''),'[^a-zA-Z0-9]','','g')) and upper(trim(coalesce(s->>'grade','')))=upper(trim(coalesce(r.grade,''))));
  if v_name is not null and v_en<>v_on then v_status:='identity_review';elsif v_entered>0 and v_matches=v_entered then v_status:='matched';else v_status:='grade_mismatch';end if;
  v_cmp:=jsonb_build_object('entered_subject_count',v_entered,'matched_subject_count',v_matches,'candidate_name_match',case when v_name is null then null else v_en=v_on end);
  update public.waec_verification_batch_candidates set reconciliation_status=v_status,official_candidate_name=v_name,official_result=v_row,comparison_result=v_cmp,reconciled_at=now() where id=v_candidate.id;
  if v_status='matched' then
   update public.applicant_qualifications set verification_status='verified',verification_source='waec_bulk',verification_reference=v_batch.batch_number,verification_notes='Automatically reconciled from WAEC bulk batch',verified_at=now(),verified_by=auth.uid(),updated_at=now() where id=v_candidate.qualification_id;
   insert into public.waec_verification_events(institution_id,application_id,applicant_id,qualification_id,verification_method,status,reference,notes,official_result,comparison_result,performed_by)values(v_inst,v_candidate.application_id,v_candidate.applicant_id,v_candidate.qualification_id,'waec_bulk','verified',v_batch.batch_number,'Automatic exact-grade reconciliation from WAEC bulk batch',v_row,v_cmp,auth.uid());
  else
   update public.applicant_qualifications set verification_status='mismatch',verification_source='waec_bulk',verification_reference=v_batch.batch_number,verification_notes=case when v_status='identity_review' then 'WAEC returned candidate identity requires review' else 'WAEC returned grades do not fully match applicant-entered grades' end,verified_at=null,verified_by=null,updated_at=now() where id=v_candidate.qualification_id;
   insert into public.waec_verification_events(institution_id,application_id,applicant_id,qualification_id,verification_method,status,reference,notes,official_result,comparison_result,performed_by)values(v_inst,v_candidate.application_id,v_candidate.applicant_id,v_candidate.qualification_id,'waec_bulk','mismatch',v_batch.batch_number,case when v_status='identity_review' then 'Identity requires review' else 'Grade mismatch during bulk reconciliation' end,v_row,v_cmp,auth.uid());
  end if;
 end loop;
 update public.waec_verification_batch_candidates set reconciliation_status='not_returned',reconciled_at=now() where batch_id=p_batch_id and reconciliation_status='pending';
 select count(*)filter(where reconciliation_status='matched'),count(*)filter(where reconciliation_status<>'matched') into v_matched,v_exceptions from public.waec_verification_batch_candidates where batch_id=p_batch_id;
 update public.waec_verification_batches set status='reconciled',matched_count=v_matched,exception_count=v_exceptions,returned_at=coalesce(returned_at,now()),reconciled_at=now(),updated_at=now() where id=p_batch_id;
 return jsonb_build_object('processed',v_processed,'matched',v_matched,'exceptions',v_exceptions);
end$$;
grant execute on function public.unimis_reconcile_waec_bulk_batch(uuid,jsonb) to authenticated;
