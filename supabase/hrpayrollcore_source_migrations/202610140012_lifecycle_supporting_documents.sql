-- Package 004c: secure supporting documents for employee lifecycle actions.
alter table public.hr_employee_lifecycle_actions
  add column if not exists supporting_file_path text,
  add column if not exists supporting_file_name text;

create or replace function public.hr_attach_lifecycle_document(
  p_tenant uuid,
  p_action uuid,
  p_file_path text,
  p_file_name text
) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then
    raise exception 'HR access denied';
  end if;
  update public.hr_employee_lifecycle_actions
     set supporting_file_path=p_file_path,
         supporting_file_name=p_file_name
   where id=p_action and tenant_id=p_tenant;
  if not found then raise exception 'Lifecycle action not found'; end if;
end $$;
grant execute on function public.hr_attach_lifecycle_document(uuid,uuid,text,text) to authenticated;

notify pgrst, 'reload schema';
