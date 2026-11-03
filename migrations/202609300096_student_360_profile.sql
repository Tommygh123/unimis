
begin;

create or replace function public.unimis_student_profile(p_student_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
 v_inst uuid;
 v_student jsonb;
begin
 select iu.institution_id into v_inst
 from public.institution_users iu
 where iu.user_id=auth.uid() and iu.status='active'
 order by iu.is_primary desc limit 1;
 if v_inst is null then raise exception 'Institution membership required'; end if;

 select to_jsonb(x) into v_student from (
   select s.id,s.student_number,s.first_name,s.middle_name,s.last_name,s.email,s.phone,
          s.gender,s.date_of_birth,s.nationality,s.address,s.city,s.region,s.status,s.student_type,
          s.photo_url,s.emergency_contact_name,s.emergency_contact_phone,s.admission_date,
          s.applicant_id,s.application_id,
          spe.id programme_enrolment_id,spe.current_level,spe.enrolment_status,spe.cohort_year,
          spe.start_date,spe.expected_completion_date,spe.completion_date,
          p.id programme_id,p.code programme_code,p.name programme_name,p.award_type,p.total_credits,
          d.id department_id,d.code department_code,d.name department_name,
          f.id faculty_id,f.code faculty_code,f.name faculty_name,
          ay.name admission_academic_year
   from public.students s
   left join public.student_programme_enrolments spe on spe.student_id=s.id and spe.is_primary=true
   left join public.programmes p on p.id=spe.programme_id
   left join public.departments d on d.id=p.department_id
   left join public.faculties f on f.id=d.faculty_id
   left join public.academic_years ay on ay.id=spe.admission_academic_year_id
   where s.id=p_student_id and s.institution_id=v_inst limit 1
 ) x;
 if v_student is null then raise exception 'Student not found'; end if;

 return v_student || jsonb_build_object(
  'guardians',coalesce((select jsonb_agg(jsonb_build_object(
    'id',g.id,'full_name',g.full_name,'relationship',g.relationship,'phone',g.phone,
    'alternate_phone',g.alternate_phone,'email',g.email,'address',g.address,'occupation',g.occupation,
    'is_primary',g.is_primary,'is_emergency_contact',g.is_emergency_contact
  ) order by g.is_primary desc,g.full_name) from public.student_guardians g where g.student_id=p_student_id),'[]'::jsonb),

  'application',(select to_jsonb(a) from (
    select ap.application_number,ap.status application_status,ap.submitted_at,
           ac.name admission_cycle
    from public.applications ap
    left join public.admission_cycles ac on ac.id=ap.admission_cycle_id
    where ap.id=(select s.application_id from public.students s where s.id=p_student_id)
    limit 1
  ) a),

  'registrations',coalesce((select jsonb_agg(to_jsonb(r) order by r.year_start desc,r.period_number desc) from (
    select spr.id,spr.level_number,spr.registration_status,spr.submitted_at,spr.approved_at,
           ay.name academic_year,ay.start_date year_start,ap.name academic_period,ap.period_number,
           (select count(*) from public.student_course_registrations scr where scr.period_registration_id=spr.id) course_count,
           coalesce((select sum(c.credit_hours) from public.student_course_registrations scr
             join public.course_offerings co on co.id=scr.course_offering_id join public.courses c on c.id=co.course_id
             where scr.period_registration_id=spr.id),0) registered_credits
    from public.student_period_registrations spr
    join public.academic_years ay on ay.id=spr.academic_year_id
    join public.academic_periods ap on ap.id=spr.academic_period_id
    where spr.student_id=p_student_id
  ) r),'[]'::jsonb),

  'results',coalesce((select jsonb_agg(to_jsonb(r) order by r.academic_year_start,r.period_number,r.course_code) from (
    select c.code course_code,c.name course_name,c.credit_hours,cr.total_score score,
           cr.letter_grade grade,cr.grade_point gp,cr.passed,cr.result_status status,
           ap.name academic_period,ap.period_number,ay.name academic_year,ay.start_date academic_year_start
    from public.course_results cr
    join public.course_offerings co on co.id=cr.course_offering_id
    join public.courses c on c.id=co.course_id
    join public.academic_periods ap on ap.id=co.academic_period_id
    join public.academic_years ay on ay.id=ap.academic_year_id
    where cr.student_id=p_student_id
  ) r),'[]'::jsonb),

  'progression',coalesce((select jsonb_agg(to_jsonb(x) order by x.acted_at desc) from (
    select h.from_level,h.to_level,h.action,h.system_decision,h.reasons,h.notes,h.acted_at,
           ay.name academic_year
    from public.student_progression_history h
    left join public.academic_years ay on ay.id=h.academic_year_id
    where h.student_id=p_student_id
  )x),'[]'::jsonb),

  'trails',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
    select c.code course_code,c.name course_name,t.credits,t.failed_score,t.failed_grade,t.status,
           ay.name source_academic_year,t.created_at,t.cleared_at
    from public.student_academic_trails t
    join public.courses c on c.id=t.course_id
    left join public.academic_years ay on ay.id=t.source_academic_year_id
    where t.student_id=p_student_id
  )x),'[]'::jsonb),

  'graduation',(select to_jsonb(x) from (
    select g.final_level,g.credits_required,g.credits_earned,g.cgpa,g.award_classification,
           g.outstanding_trails,g.decision,g.reasons,g.evaluated_at,g.approved_at,g.graduation_date,
           ay.name academic_year
    from public.graduation_reviews g
    left join public.academic_years ay on ay.id=g.academic_year_id
    where g.student_id=p_student_id
    order by g.evaluated_at desc limit 1
  )x),

  'status_history',coalesce((select jsonb_agg(jsonb_build_object(
    'old_status',h.old_status,'new_status',h.new_status,'reason',h.reason,
    'effective_date',h.effective_date,'created_at',h.created_at
  ) order by h.effective_date desc,h.created_at desc)
  from public.student_status_history h where h.student_id=p_student_id),'[]'::jsonb),

  'documents',coalesce((select jsonb_agg(jsonb_build_object(
    'id',d.id,'document_type',d.document_type,'file_name',d.file_name,'mime_type',d.mime_type,'created_at',d.created_at
  ) order by d.created_at desc) from public.student_documents d where d.student_id=p_student_id),'[]'::jsonb),

  'finance',jsonb_build_object(
    'invoiced',coalesce((select sum(total_amount) from public.student_invoices where student_id=p_student_id and status<>'cancelled'),0),
    'paid',coalesce((select sum(amount) from public.student_payments where student_id=p_student_id and status='completed'),0),
    'balance',coalesce((select sum(balance) from public.student_invoices where student_id=p_student_id and status not in ('cancelled','waived')),0)
  )
 );
end $$;

grant execute on function public.unimis_student_profile(uuid) to authenticated;

commit;
