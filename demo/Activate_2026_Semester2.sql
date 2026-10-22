-- Local test school only. Promotion remains an authorised Registrar action.
begin;
do $$begin if not exists(select 1 from public.institutions where id='bf51a84f-2745-5986-99df-96e34b584049' and code='UNIMIS-E2E-117') then raise exception 'Test school not installed'; end if; end $$;
update public.academic_periods set is_current=false where institution_id='bf51a84f-2745-5986-99df-96e34b584049';
update public.academic_years set is_current=false where institution_id='bf51a84f-2745-5986-99df-96e34b584049';
update public.academic_years set is_current=true,status='active' where id='433163b5-a5f4-519c-80e5-08933b259deb' and institution_id='bf51a84f-2745-5986-99df-96e34b584049';
update public.academic_periods set is_current=true,status='active',registration_start=current_date-1,registration_end=current_date+90 where id='b51e6dea-243c-5543-b4ac-14ac7f75b812' and institution_id='bf51a84f-2745-5986-99df-96e34b584049';
commit;
