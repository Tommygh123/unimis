-- Local test school only. Promotion remains an authorised Registrar action.
begin;
do $$begin if not exists(select 1 from public.institutions where id='bf51a84f-2745-5986-99df-96e34b584049' and code='UNIMIS-E2E-117') then raise exception 'Test school not installed'; end if; end $$;
update public.academic_periods set is_current=false where institution_id='bf51a84f-2745-5986-99df-96e34b584049';
update public.academic_years set is_current=false where institution_id='bf51a84f-2745-5986-99df-96e34b584049';
update public.academic_years set is_current=true,status='active' where id='15a3a7c0-d2ba-5795-8911-95617ed6e5c3' and institution_id='bf51a84f-2745-5986-99df-96e34b584049';
update public.academic_periods set is_current=true,status='active',registration_start=current_date-1,registration_end=current_date+90 where id='8f910d42-e096-5505-a740-c2c37d9249e3' and institution_id='bf51a84f-2745-5986-99df-96e34b584049';
commit;
