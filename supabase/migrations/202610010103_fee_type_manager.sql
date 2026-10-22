begin;

create or replace function public.unimis_create_fee_type(p_name text,p_code text default null,p_description text default null,p_is_mandatory boolean default true)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution(); v_id uuid; v_code text;
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 if nullif(btrim(p_name),'') is null then raise exception 'Fee type name is required'; end if;
 v_code:=upper(regexp_replace(coalesce(nullif(btrim(p_code),''),left(btrim(p_name),12)),'[^A-Za-z0-9]+','_','g'));
 if exists(select 1 from public.fee_types where institution_id=v_inst and lower(name)=lower(btrim(p_name))) then
   raise exception 'A fee type named "%" already exists',btrim(p_name);
 end if;
 if exists(select 1 from public.fee_types where institution_id=v_inst and code=v_code) then
   v_code:=v_code||'_'||substr(replace(gen_random_uuid()::text,'-',''),1,4);
 end if;
 insert into public.fee_types(institution_id,code,name,description,is_mandatory,status)
 values(v_inst,v_code,btrim(p_name),nullif(btrim(p_description),''),coalesce(p_is_mandatory,true),'active')
 returning id into v_id;
 return jsonb_build_object('ok',true,'id',v_id,'code',v_code,'name',btrim(p_name));
end $$;
grant execute on function public.unimis_create_fee_type(text,text,text,boolean) to authenticated;

commit;
notify pgrst,'reload schema';
