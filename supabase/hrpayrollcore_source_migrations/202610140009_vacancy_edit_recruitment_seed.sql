-- Package 003f: recruitment test seed helper. Production data is untouched.
create or replace function public.seed_recruitment_test(p_tenant uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_vacancy uuid; v_title text; a1 uuid; a2 uuid; a3 uuid; a4 uuid; a5 uuid;
begin
  if not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then
    raise exception 'Recruitment seed access denied';
  end if;

  select id,title into v_vacancy,v_title from public.hr_vacancies
   where tenant_id=p_tenant and status='published'
   order by published_at desc nulls last, created_at desc limit 1;
  if v_vacancy is null then
    raise exception 'Publish at least one vacancy before loading the recruitment test seed';
  end if;

  -- Idempotent demo seed: remove only our known, non-hired test candidates.
  delete from public.hr_applicants
   where tenant_id=p_tenant and email like 'recruit.test.%@hrpayrollcore.local' and status <> 'hired';

  insert into public.hr_applicants(tenant_id,vacancy_id,first_name,last_name,email,phone,date_of_birth,source,status,highest_qualification,years_experience,key_skills,screening_score,screening_notes)
  values(p_tenant,v_vacancy,'Adwoa','Owusu','recruit.test.1@hrpayrollcore.local','0240001001','1995-04-12','Seed test','applied','BSc Business Administration',3,'Administration, records, Microsoft Office',72,'Meets basic requirements') returning id into a1;

  insert into public.hr_applicants(tenant_id,vacancy_id,first_name,last_name,email,phone,date_of_birth,source,status,highest_qualification,years_experience,key_skills,screening_score,screening_notes)
  values(p_tenant,v_vacancy,'Kofi','Boateng','recruit.test.2@hrpayrollcore.local','0240001002','1992-09-21','Seed test','shortlisted','HND Accounting',5,'Accounting, Excel, reconciliation',84,'Strong relevant experience') returning id into a2;

  insert into public.hr_applicants(tenant_id,vacancy_id,first_name,last_name,email,phone,date_of_birth,source,status,highest_qualification,years_experience,key_skills,screening_score,screening_notes)
  values(p_tenant,v_vacancy,'Akosua','Mensimah','recruit.test.3@hrpayrollcore.local','0240001003','1997-01-08','Seed test','shortlisted','BCom',2,'Customer service, reporting, Excel',80,'Suitable for interview') returning id into a3;

  insert into public.hr_applicants(tenant_id,vacancy_id,first_name,last_name,email,phone,date_of_birth,source,status,highest_qualification,years_experience,key_skills,screening_score,screening_notes)
  values(p_tenant,v_vacancy,'Yaw','Asante','recruit.test.4@hrpayrollcore.local','0240001004','1993-07-15','Seed test','interviewed','BSc Accounting',6,'Accounting, ERP, reporting',91,'Interview completed; strong recommendation') returning id into a4;
  insert into public.hr_interviews(tenant_id,applicant_id,interview_at,interview_type,panel_notes,score,recommendation,created_by)
  values(p_tenant,a4,now()-interval '1 day','in_person','Clear communication and strong practical examples.',88,'Recommended for selection',auth.uid());

  insert into public.hr_applicants(tenant_id,vacancy_id,first_name,last_name,email,phone,date_of_birth,source,status,highest_qualification,years_experience,key_skills,screening_score,screening_notes,selected_at)
  values(p_tenant,v_vacancy,'Esi','Agyeman','recruit.test.5@hrpayrollcore.local','0240001005','1991-11-30','Seed test','offer_accepted','BSc Accounting',7,'Accounting, payroll, ERP, supervision',95,'Preferred candidate after interview',now()-interval '2 days') returning id into a5;
  insert into public.hr_interviews(tenant_id,applicant_id,interview_at,interview_type,panel_notes,score,recommendation,created_by)
  values(p_tenant,a5,now()-interval '3 days','in_person','Excellent technical and behavioural interview.',94,'Select',auth.uid());
  insert into public.hr_offers(tenant_id,applicant_id,offered_salary,proposed_start_date,employment_type,status,issued_at,responded_at,created_by)
  values(p_tenant,a5,4500,current_date+7,'regular','accepted',now()-interval '2 days',now()-interval '1 day',auth.uid());

  return jsonb_build_object('message','5 test applicants added to '||v_title||'. Final Hire is intentionally left for manual testing.','vacancy_id',v_vacancy,'hire_ready_applicant',a5);
end $$;
grant execute on function public.seed_recruitment_test(uuid) to authenticated;
notify pgrst, 'reload schema';
