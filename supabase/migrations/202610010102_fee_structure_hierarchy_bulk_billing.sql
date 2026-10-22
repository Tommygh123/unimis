begin;

-- Fee structures can now be scoped to faculty and/or department as well as programme.
alter table public.fee_structures add column if not exists faculty_id uuid references public.faculties(id) on delete set null;
alter table public.fee_structures add column if not exists department_id uuid references public.departments(id) on delete set null;
alter table public.fee_structures add column if not exists auto_invoice boolean not null default true;

create index if not exists ix_fee_structures_scope102
on public.fee_structures(institution_id,academic_year_id,academic_period_id,faculty_id,department_id,programme_id,level_number,student_type,status);

create or replace function public.unimis_finance_setup()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution();
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 return jsonb_build_object(
 'academic_years',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'is_current',is_current) order by start_date desc) from public.academic_years where institution_id=v_inst),'[]'::jsonb),
 'periods',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'academic_year_id',academic_year_id,'is_current',is_current) order by start_date desc) from public.academic_periods where institution_id=v_inst),'[]'::jsonb),
 'faculties',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name) order by name) from public.faculties where institution_id=v_inst and status='active'),'[]'::jsonb),
 'departments',coalesce((select jsonb_agg(jsonb_build_object('id',id,'faculty_id',faculty_id,'code',code,'name',name) order by name) from public.departments where institution_id=v_inst and status='active'),'[]'::jsonb),
 'programmes',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'department_id',p.department_id,'faculty_id',d.faculty_id,'code',p.code,'name',p.name) order by p.code) from public.programmes p left join public.departments d on d.id=p.department_id where p.institution_id=v_inst and p.status='active'),'[]'::jsonb),
 'fee_types',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'is_mandatory',is_mandatory) order by name) from public.fee_types where institution_id=v_inst and status='active'),'[]'::jsonb),
 'students',coalesce((select jsonb_agg(to_jsonb(x) order by x.student_number) from (
   select s.id,s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) name,s.student_type,e.programme_id,e.current_level,p.code programme_code,p.department_id,d.faculty_id
   from public.students s
   left join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true
   left join public.programmes p on p.id=e.programme_id
   left join public.departments d on d.id=p.department_id
   where s.institution_id=v_inst and s.status='active'
 )x),'[]'::jsonb)
 );
end $$;

create or replace function public.unimis_save_fee_structure(p_structure jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution(); v_id uuid; x jsonb; v_type uuid; v_name text;
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 if nullif(p_structure->>'academic_year_id','') is null then raise exception 'Academic year is required'; end if;
 if coalesce(jsonb_array_length(p_structure->'items'),0)=0 then raise exception 'Add at least one fee item'; end if;
 v_name:=nullif(btrim(coalesce(p_structure->>'name','')),'');
 if v_name is null then
   select concat_ws(' • ',
     coalesce((select p.code from public.programmes p where p.id=nullif(p_structure->>'programme_id','')::uuid),
              (select d.code from public.departments d where d.id=nullif(p_structure->>'department_id','')::uuid),
              (select f.code from public.faculties f where f.id=nullif(p_structure->>'faculty_id','')::uuid),'Institution'),
     case when nullif(p_structure->>'level_number','') is not null then 'Level '||(p_structure->>'level_number') else 'All Levels' end,
     coalesce(nullif(initcap(p_structure->>'student_type'),''),'All Students'),
     coalesce((select ap.name from public.academic_periods ap where ap.id=nullif(p_structure->>'academic_period_id','')::uuid),'All Periods'),
     (select ay.name from public.academic_years ay where ay.id=(p_structure->>'academic_year_id')::uuid)
   ) into v_name;
 end if;
 if nullif(p_structure->>'id','') is null then
  insert into public.fee_structures(institution_id,academic_year_id,academic_period_id,faculty_id,department_id,programme_id,level_number,student_type,name,status,currency_code,auto_invoice)
  values(v_inst,(p_structure->>'academic_year_id')::uuid,nullif(p_structure->>'academic_period_id','')::uuid,nullif(p_structure->>'faculty_id','')::uuid,nullif(p_structure->>'department_id','')::uuid,nullif(p_structure->>'programme_id','')::uuid,nullif(p_structure->>'level_number','')::int,nullif(p_structure->>'student_type',''),v_name,coalesce(nullif(p_structure->>'status',''),'active'),coalesce(nullif(p_structure->>'currency_code',''),'GHS'),coalesce((p_structure->>'auto_invoice')::boolean,true)) returning id into v_id;
 else
  v_id:=(p_structure->>'id')::uuid;
  if not exists(select 1 from public.fee_structures where id=v_id and institution_id=v_inst) then raise exception 'Fee structure not found'; end if;
  update public.fee_structures set academic_year_id=(p_structure->>'academic_year_id')::uuid,academic_period_id=nullif(p_structure->>'academic_period_id','')::uuid,faculty_id=nullif(p_structure->>'faculty_id','')::uuid,department_id=nullif(p_structure->>'department_id','')::uuid,programme_id=nullif(p_structure->>'programme_id','')::uuid,level_number=nullif(p_structure->>'level_number','')::int,student_type=nullif(p_structure->>'student_type',''),name=v_name,status=coalesce(nullif(p_structure->>'status',''),'active'),currency_code=coalesce(nullif(p_structure->>'currency_code',''),'GHS'),auto_invoice=coalesce((p_structure->>'auto_invoice')::boolean,true),updated_at=now() where id=v_id;
  delete from public.fee_structure_items where fee_structure_id=v_id;
 end if;
 for x in select * from jsonb_array_elements(p_structure->'items') loop
  v_type=nullif(x->>'fee_type_id','')::uuid;
  if v_type is null then raise exception 'Every fee item requires a fee type'; end if;
  insert into public.fee_structure_items(institution_id,fee_structure_id,fee_type_id,amount,due_date,is_optional)
  values(v_inst,v_id,v_type,coalesce((x->>'amount')::numeric,0),nullif(x->>'due_date','')::date,coalesce((x->>'is_optional')::boolean,false));
 end loop;
 return jsonb_build_object('ok',true,'id',v_id,'name',v_name);
end $$;

create or replace function public.unimis_fee_structure_detail(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution();
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 return (select jsonb_build_object('id',fs.id,'name',fs.name,'academic_year_id',fs.academic_year_id,'academic_period_id',fs.academic_period_id,'faculty_id',fs.faculty_id,'department_id',fs.department_id,'programme_id',fs.programme_id,'level_number',fs.level_number,'student_type',fs.student_type,'currency_code',fs.currency_code,'status',fs.status,'auto_invoice',fs.auto_invoice,
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'fee_type_id',i.fee_type_id,'fee_type',ft.name,'amount',i.amount,'due_date',i.due_date,'is_optional',i.is_optional) order by ft.name) from public.fee_structure_items i join public.fee_types ft on ft.id=i.fee_type_id where i.fee_structure_id=fs.id),'[]'::jsonb))
 from public.fee_structures fs where fs.id=p_id and fs.institution_id=v_inst);
end $$;

-- Replace the old resolver with a hierarchy-aware resolver.
create or replace function public.unimis_generate_student_initial_invoice(p_student_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_student public.students%rowtype; v_enrol public.student_programme_enrolments%rowtype;
 v_year public.academic_years%rowtype; v_period public.academic_periods%rowtype;
 v_structure public.fee_structures%rowtype; v_invoice public.student_invoices%rowtype;
 v_seq bigint; v_total numeric:=0; v_department uuid; v_faculty uuid;
begin
 select * into v_student from public.students where id=p_student_id;
 if not found then raise exception 'Student not found'; end if;
 if not (public.has_permission(v_student.institution_id,'finance.manage') or public.has_permission(v_student.institution_id,'students.manage')) then raise exception 'You do not have permission to generate student invoices'; end if;
 select * into v_enrol from public.student_programme_enrolments where student_id=p_student_id and is_primary=true and enrolment_status in ('admitted','active') order by created_at desc limit 1;
 if not found then return jsonb_build_object('ok',false,'reason','no_active_enrolment','message','Student has no active/admitted primary programme enrolment.'); end if;
 select p.department_id,d.faculty_id into v_department,v_faculty from public.programmes p left join public.departments d on d.id=p.department_id where p.id=v_enrol.programme_id;
 select * into v_year from public.academic_years where institution_id=v_student.institution_id and is_current=true order by start_date desc limit 1;
 if not found then raise exception 'No current academic year configured'; end if;
 select * into v_period from public.academic_periods where institution_id=v_student.institution_id and academic_year_id=v_year.id and is_current=true order by period_number limit 1;
 if exists(select 1 from public.student_invoices where student_id=p_student_id and academic_year_id=v_year.id and academic_period_id is not distinct from v_period.id and status<>'cancelled') then
  select * into v_invoice from public.student_invoices where student_id=p_student_id and academic_year_id=v_year.id and academic_period_id is not distinct from v_period.id and status<>'cancelled' order by created_at desc limit 1;
  return jsonb_build_object('ok',true,'already_exists',true,'invoice_id',v_invoice.id,'invoice_number',v_invoice.invoice_number);
 end if;
 select * into v_structure from public.fee_structures fs
 where fs.institution_id=v_student.institution_id and fs.academic_year_id=v_year.id and fs.status='active'
 and (fs.academic_period_id is null or fs.academic_period_id=v_period.id)
 and (fs.faculty_id is null or fs.faculty_id=v_faculty)
 and (fs.department_id is null or fs.department_id=v_department)
 and (fs.programme_id is null or fs.programme_id=v_enrol.programme_id)
 and (fs.level_number is null or fs.level_number=v_enrol.current_level)
 and (fs.student_type is null or fs.student_type=v_student.student_type)
 order by
  (fs.programme_id is not null)::int desc,
  (fs.department_id is not null)::int desc,
  (fs.faculty_id is not null)::int desc,
  (fs.level_number is not null)::int desc,
  (fs.student_type is not null)::int desc,
  (fs.academic_period_id is not null)::int desc,
  fs.updated_at desc limit 1;
 if not found then return jsonb_build_object('ok',false,'reason','no_fee_structure','message','No matching active fee structure is configured.'); end if;
 insert into public.student_invoice_sequences(institution_id,academic_year,last_number) values(v_student.institution_id,extract(year from v_year.start_date)::integer,1)
 on conflict(institution_id,academic_year) do update set last_number=public.student_invoice_sequences.last_number+1,updated_at=now() returning last_number into v_seq;
 select coalesce(sum(amount),0) into v_total from public.fee_structure_items where fee_structure_id=v_structure.id;
 insert into public.student_invoices(institution_id,student_id,academic_year_id,academic_period_id,invoice_number,invoice_date,currency_code,subtotal,total_amount,amount_paid,balance,status,notes,created_by)
 values(v_student.institution_id,v_student.id,v_year.id,v_period.id,'INV/'||extract(year from v_year.start_date)::integer||'/'||lpad(v_seq::text,6,'0'),current_date,v_structure.currency_code,v_total,v_total,0,v_total,case when v_total=0 then 'paid' else 'unpaid' end,'Invoice generated from fee structure: '||v_structure.name,auth.uid()) returning * into v_invoice;
 insert into public.student_invoice_items(institution_id,invoice_id,fee_type_id,description,quantity,unit_amount,line_total)
 select v_student.institution_id,v_invoice.id,fsi.fee_type_id,coalesce(ft.name,'Student fee'),1,fsi.amount,fsi.amount from public.fee_structure_items fsi left join public.fee_types ft on ft.id=fsi.fee_type_id where fsi.fee_structure_id=v_structure.id;
 return jsonb_build_object('ok',true,'invoice_id',v_invoice.id,'invoice_number',v_invoice.invoice_number,'fee_structure_id',v_structure.id,'fee_structure_name',v_structure.name,'total_amount',v_invoice.total_amount,'currency',v_invoice.currency_code);
end $$;

-- Bulk invoicing for the current year/period. Filters are optional.
create or replace function public.unimis_generate_period_fee_invoices(p_faculty_id uuid default null,p_department_id uuid default null,p_programme_id uuid default null,p_level integer default null,p_student_type text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution(); r record; x jsonb; v_ok int:=0; v_existing int:=0; v_skipped int:=0; v_fail jsonb:='[]'::jsonb;
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 for r in
  select s.id from public.students s join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true and e.enrolment_status in ('admitted','active')
  join public.programmes p on p.id=e.programme_id left join public.departments d on d.id=p.department_id
  where s.institution_id=v_inst and s.status='active'
    and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id)
    and (p_programme_id is null or e.programme_id=p_programme_id) and (p_level is null or e.current_level=p_level)
    and (p_student_type is null or s.student_type=p_student_type)
 loop
  begin
   x:=public.unimis_generate_fee_invoice(r.id);
   if coalesce((x->>'ok')::boolean,false) then
     if coalesce((x->>'already_exists')::boolean,false) then v_existing:=v_existing+1; else v_ok:=v_ok+1; end if;
   else v_skipped:=v_skipped+1; v_fail:=v_fail||jsonb_build_array(jsonb_build_object('student_id',r.id,'message',x->>'message')); end if;
  exception when others then v_skipped:=v_skipped+1; v_fail:=v_fail||jsonb_build_array(jsonb_build_object('student_id',r.id,'message',sqlerrm)); end;
 end loop;
 return jsonb_build_object('ok',true,'generated',v_ok,'already_invoiced',v_existing,'skipped',v_skipped,'details',v_fail);
end $$;

grant execute on function public.unimis_finance_setup() to authenticated;
grant execute on function public.unimis_save_fee_structure(jsonb) to authenticated;
grant execute on function public.unimis_fee_structure_detail(uuid) to authenticated;
grant execute on function public.unimis_generate_student_initial_invoice(uuid) to authenticated;
grant execute on function public.unimis_generate_period_fee_invoices(uuid,uuid,uuid,integer,text) to authenticated;

commit;
notify pgrst,'reload schema';
