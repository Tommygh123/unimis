-- UniMIS 155: controlled multi-institution onboarding foundation
-- No demo/transaction data is copied. Platform operator only.

create table if not exists public.unimis_institution_onboarding155(
 institution_id uuid primary key references public.institutions(id) on delete cascade,
 owner_email text,
 owner_first_name text,
 owner_last_name text,
 owner_status text not null default 'not_set' check(owner_status in('not_set','awaiting_registration','assigned')),
 go_live_status text not null default 'setup' check(go_live_status in('setup','ready','live','suspended')),
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.institution_workflow_status(
 institution_id uuid not null references public.institutions(id) on delete cascade,
 step_key text not null,
 is_complete boolean not null default false,
 completed_at timestamptz,
 primary key(institution_id,step_key)
);

alter table public.unimis_institution_onboarding155 enable row level security;
alter table public.institution_workflow_status enable row level security;

drop policy if exists "Institution members read workflow status" on public.institution_workflow_status;
create policy "Institution members read workflow status" on public.institution_workflow_status
for select to authenticated using(
 exists(select 1 from public.institution_users iu where iu.institution_id=institution_workflow_status.institution_id and iu.user_id=auth.uid() and iu.status='active')
 or public.unimis_is_platform_operator116()
);

revoke all on public.unimis_institution_onboarding155 from public,anon,authenticated;
grant select on public.institution_workflow_status to authenticated;

create or replace function public.unimis_platform_create_institution155(
 p_name text,p_short_name text,p_code text,p_type text,p_email text default null,p_phone text default null,
 p_country text default 'Ghana',p_region text default null,p_city text default null,
 p_owner_email text default null,p_owner_first_name text default null,p_owner_last_name text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_inst uuid; v_owner_role uuid; v_user uuid; v_owner_status text:='not_set'; v_template uuid;
begin
 if not public.unimis_is_platform_operator116() then raise exception 'Protected platform operator required'; end if;
 if nullif(btrim(p_name),'') is null or nullif(btrim(p_code),'') is null then raise exception 'Institution name and code are required'; end if;
 if p_type not in('jhs','shs','university','college','technical','vocational','other') then raise exception 'Invalid institution type'; end if;
 if exists(select 1 from public.institutions where upper(code)=upper(btrim(p_code))) then raise exception 'Institution code already exists'; end if;

 insert into public.institutions(name,short_name,code,institution_type,email,phone,country,region,city,status)
 values(btrim(p_name),nullif(btrim(p_short_name),''),upper(btrim(p_code)),p_type,nullif(btrim(p_email),''),nullif(btrim(p_phone),''),coalesce(nullif(btrim(p_country),''),'Ghana'),nullif(btrim(p_region),''),nullif(btrim(p_city),''),'active')
 returning id into v_inst;

 insert into public.institution_settings(institution_id) values(v_inst) on conflict(institution_id) do nothing;

 select id into v_template from public.institutions where code='UNIMIS-DEMO-UNIV' limit 1;
 if v_template is not null then
   insert into public.roles(institution_id,name,code,description,is_system_role,is_active)
   select v_inst,name,code,description,false,is_active from public.roles where institution_id=v_template
   on conflict(institution_id,code) do nothing;
   insert into public.role_permissions(role_id,permission_id)
   select nr.id,rp.permission_id
   from public.roles tr join public.role_permissions rp on rp.role_id=tr.id
   join public.roles nr on nr.institution_id=v_inst and nr.code=tr.code
   where tr.institution_id=v_template
   on conflict do nothing;
 end if;

 if not exists(select 1 from public.roles where institution_id=v_inst and code='owner') then
   insert into public.roles(institution_id,name,code,description,is_system_role,is_active)
   values(v_inst,'Owner','owner','Institution owner / highest-level administrator',false,true);
 end if;
 select id into v_owner_role from public.roles where institution_id=v_inst and code='owner';

 insert into public.institution_workflow_status(institution_id,step_key)
 select v_inst,x from unnest(array['institution_configured','academic_structure_configured','admissions_ready','student_records_ready','teaching_ready','results_ready']) x
 on conflict do nothing;

 if nullif(btrim(p_owner_email),'') is not null then
   select id into v_user from auth.users where lower(email)=lower(btrim(p_owner_email)) limit 1;
   if v_user is not null then
     insert into public.profiles(id,first_name,last_name,display_name,status)
     values(v_user,nullif(btrim(p_owner_first_name),''),nullif(btrim(p_owner_last_name),''),nullif(btrim(concat_ws(' ',p_owner_first_name,p_owner_last_name)),''),'active')
     on conflict(id) do update set
       first_name=coalesce(public.profiles.first_name,excluded.first_name),
       last_name=coalesce(public.profiles.last_name,excluded.last_name),
       display_name=coalesce(public.profiles.display_name,excluded.display_name);
     insert into public.institution_users(institution_id,user_id,role_id,status,is_primary)
     values(v_inst,v_user,v_owner_role,'active',true)
     on conflict(institution_id,user_id) do update set role_id=excluded.role_id,status='active',is_primary=true;
     v_owner_status:='assigned';
   else
     v_owner_status:='awaiting_registration';
   end if;
 end if;

 insert into public.unimis_institution_onboarding155(institution_id,owner_email,owner_first_name,owner_last_name,owner_status,created_by)
 values(v_inst,nullif(lower(btrim(p_owner_email)),''),nullif(btrim(p_owner_first_name),''),nullif(btrim(p_owner_last_name),''),v_owner_status,auth.uid());

 return jsonb_build_object('institution_id',v_inst,'owner_status',v_owner_status);
end $$;

revoke all on function public.unimis_platform_create_institution155(text,text,text,text,text,text,text,text,text,text,text,text) from public;
grant execute on function public.unimis_platform_create_institution155(text,text,text,text,text,text,text,text,text,text,text,text) to authenticated;

create or replace function public.unimis_platform_institutions155()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.unimis_is_platform_operator116() then raise exception 'Protected platform operator required'; end if;
 return coalesce((
  select jsonb_agg(jsonb_build_object(
   'id',i.id,'name',i.name,'short_name',i.short_name,'code',i.code,'institution_type',i.institution_type,'status',i.status,
   'owner_email',o.owner_email,'owner_status',o.owner_status,'go_live_status',coalesce(o.go_live_status,'setup'),
   'completed_steps',(select count(*) from public.institution_workflow_status w where w.institution_id=i.id and w.is_complete),
   'total_steps',6,
   'readiness_percent',round(100.0*(select count(*) from public.institution_workflow_status w where w.institution_id=i.id and w.is_complete)/6)
  ) order by i.created_at desc)
  from public.institutions i left join public.unimis_institution_onboarding155 o on o.institution_id=i.id
 ),'[]'::jsonb);
end $$;

revoke all on function public.unimis_platform_institutions155() from public;
grant execute on function public.unimis_platform_institutions155() to authenticated;
