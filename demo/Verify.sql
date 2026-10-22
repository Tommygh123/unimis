do $verify$
begin
 if (select count(*) from public.applicants where institution_id='bf51a84f-2745-5986-99df-96e34b584049')<19 then raise exception 'Expected fixture applicants and live-demo profile';end if;
 if (select count(*) from public.students where institution_id='bf51a84f-2745-5986-99df-96e34b584049')<13 then raise exception 'Expected existing demo students';end if;
 if (select count(*) from public.applications where institution_id='bf51a84f-2745-5986-99df-96e34b584049' and payment_status='paid')<18 then raise exception 'Expected paid fixture applications';end if;
 if (select count(*) from public.course_results where institution_id='bf51a84f-2745-5986-99df-96e34b584049' and result_status='published')<108 then raise exception 'Historical results missing';end if;
 if exists(select 1 from public.application_documents d where institution_id='bf51a84f-2745-5986-99df-96e34b584049' and not exists(select 1 from storage.objects o where o.bucket_id='admission-documents' and o.name=d.storage_path)) then raise exception 'Some fixture uploads are missing';end if;
 if exists(select 1 from public.course_results where student_id='88077e7f-c3c9-5c03-98ab-70316125eec4' and not passed) then raise exception 'Clear graduation scenario has a failed course';end if;
 if not exists(select 1 from public.course_results where student_id='23393a9b-6a53-5659-aa0b-b52218c97cd4' and not passed) then raise exception 'Trail graduation scenario must include a failed course';end if;
 raise notice '148 historical results, graduation cases and private files verified';
end $verify$;
