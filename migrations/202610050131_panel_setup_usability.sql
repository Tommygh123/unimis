-- Idempotent panel creation; preserve existing panels, appointments and review history.
create or replace function public.unimis_create_committee130(p_inst uuid,p_name text,p_stage text,p_department uuid,p_faculty uuid,p_quorum int)
returns uuid language plpgsql security definer set search_path='' as $$
declare rid uuid;
begin
 if not public.unimis_review_manager130(p_inst) then raise exception 'Academic review coordination required';end if;
 if length(trim(coalesce(p_name,'')))<3 or p_quorum is null or p_quorum<2 then raise exception 'Committee name and quorum of at least two required';end if;
 if p_stage='department' then
 if p_faculty is not null or not exists(select 1 from public.departments where id=p_department and institution_id=p_inst) then raise exception 'Choose a department within this school';end if;
 elsif p_stage='faculty' then
 if p_department is not null or not exists(select 1 from public.faculties where id=p_faculty and institution_id=p_inst) then raise exception 'Choose a faculty within this school';end if;
 elsif p_stage in ('audit','college','academic_board','central','final') then
 if p_department is not null or p_faculty is not null then raise exception 'This stage uses explicitly assigned school batches';end if;
 else raise exception 'Invalid review stage';end if;
 perform 1 from public.institutions where id=p_inst for update;
 select id into rid from public.unimis_committees130 where institution_id=p_inst and lower(trim(name))=lower(trim(p_name)) and stage=p_stage and department_id is not distinct from p_department and faculty_id is not distinct from p_faculty order by created_at,id limit 1;
 if rid is not null then return rid;end if;
 insert into public.unimis_committees130(institution_id,name,stage,department_id,faculty_id,quorum,created_by)
 values(p_inst,trim(p_name),p_stage,p_department,p_faculty,p_quorum,auth.uid()) returning id into rid;return rid;
end $$;

create or replace function public.unimis_assign_panel_members131(p_committee uuid,p_users uuid[],p_responsibility text)
returns void language plpgsql security definer set search_path='' as $$
declare u uuid;
begin
 if coalesce(cardinality(p_users),0)=0 then raise exception 'Select at least one staff member';end if;
 if p_responsibility not in ('chair','secretary','member','remove') then raise exception 'Invalid panel responsibility';end if;
 if p_responsibility in ('chair','secretary') and cardinality(p_users)<>1 then raise exception 'Select exactly one chair or secretary';end if;
 for u in select distinct unnest(p_users) loop
 perform public.unimis_assign_panel_member130(p_committee,u,p_responsibility);
 end loop;
end $$;
revoke all on function public.unimis_assign_panel_members131(uuid,uuid[],text) from public,anon;
grant execute on function public.unimis_assign_panel_members131(uuid,uuid[],text) to authenticated;
