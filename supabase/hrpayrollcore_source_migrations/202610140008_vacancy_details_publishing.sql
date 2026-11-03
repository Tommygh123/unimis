-- Package 003b: richer vacancy specification and controlled publishing workflow.
alter table public.hr_vacancies add column if not exists responsibilities text;
alter table public.hr_vacancies add column if not exists experience_required text;
alter table public.hr_vacancies add column if not exists conditions_text text;
alter table public.hr_vacancies add column if not exists location_text text;
alter table public.hr_vacancies add column if not exists work_arrangement text not null default 'on_site';
alter table public.hr_vacancies add column if not exists cv_required boolean not null default true;
alter table public.hr_vacancies add column if not exists published_at timestamptz;
alter table public.hr_vacancies add column if not exists approved_at timestamptz;
alter table public.hr_vacancies add column if not exists approved_by uuid references auth.users(id) on delete set null;

update public.hr_vacancies set status='published',published_at=coalesce(published_at,created_at) where status='open';

alter table public.hr_vacancies drop constraint if exists hr_vacancies_status_check;
alter table public.hr_vacancies add constraint hr_vacancies_status_check check(status in ('draft','pending_approval','approved','published','closed','cancelled'));
alter table public.hr_vacancies drop constraint if exists hr_vacancies_work_arrangement_check;
alter table public.hr_vacancies add constraint hr_vacancies_work_arrangement_check check(work_arrangement in ('on_site','hybrid','remote'));

create index if not exists hr_vacancies_public_idx on public.hr_vacancies(tenant_id,status,closing_date);

-- Keep approval metadata when an authorised HR user moves a vacancy through review.
create or replace function public.hr_set_vacancy_status(p_tenant uuid,p_vacancy uuid,p_status text)
returns public.hr_vacancies language plpgsql security definer set search_path=public as $$
declare v public.hr_vacancies;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'Vacancy workflow access denied'; end if;
 if p_status not in ('draft','pending_approval','approved','published','closed','cancelled') then raise exception 'Invalid vacancy status'; end if;
 select * into v from public.hr_vacancies where id=p_vacancy and tenant_id=p_tenant for update;
 if v.id is null then raise exception 'Vacancy not found'; end if;
 if p_status='approved' and not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Approval access denied'; end if;
 update public.hr_vacancies set status=p_status,
   approved_at=case when p_status='approved' then now() else approved_at end,
   approved_by=case when p_status='approved' then auth.uid() else approved_by end,
   published_at=case when p_status='published' then now() else published_at end
 where id=p_vacancy returning * into v;
 return v;
end $$;
grant execute on function public.hr_set_vacancy_status(uuid,uuid,text) to authenticated;
notify pgrst, 'reload schema';
