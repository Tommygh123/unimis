-- Package 007d1: correct Employee Master edit mapping.
-- pay_basis belongs to hr_employment_contracts, not hr_employees.
create or replace function public.hr_update_employee_master(
 p_tenant uuid,p_employee uuid,p_first_name text,p_last_name text,p_email text,p_phone text,
 p_date_of_birth date,p_gender text,p_marital_status text,p_nationality text,p_national_id text,p_address text,
 p_department uuid,p_position uuid,p_employment_type text,p_work_schedule text,p_pay_basis text,
 p_basic_salary numeric,p_salary_effective date,p_ssnit_number text,p_tax_number text,
 p_bank_name text,p_bank_branch text,p_bank_account_name text,p_bank_account_number text,
 p_payment_method text,p_momo_network text,p_momo_number text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare old_salary numeric(14,2); active_contract uuid; result jsonb;
begin
 if not is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if not exists(select 1 from hr_employees where id=p_employee and tenant_id=p_tenant) then raise exception 'Employee not found'; end if;
 if p_pay_basis not in ('monthly','weekly','daily','hourly') then raise exception 'Invalid pay basis'; end if;
 select id,basic_salary into active_contract,old_salary from hr_employment_contracts where tenant_id=p_tenant and employee_id=p_employee and status='active' order by start_date desc limit 1;
 old_salary:=coalesce((select sh.new_salary from hr_salary_history sh where sh.employee_id=p_employee and sh.effective_from<=coalesce(p_salary_effective,current_date) order by sh.effective_from desc,sh.created_at desc limit 1),old_salary,0);
 update hr_employees set first_name=p_first_name,last_name=p_last_name,email=nullif(p_email,''),phone=nullif(p_phone,''),date_of_birth=p_date_of_birth,gender=nullif(p_gender,''),marital_status=nullif(p_marital_status,''),nationality=nullif(p_nationality,''),national_id=nullif(p_national_id,''),residential_address=nullif(p_address,''),department_id=p_department,position_id=p_position,employment_type=p_employment_type,work_schedule=p_work_schedule where id=p_employee and tenant_id=p_tenant;
 if active_contract is not null then
   update hr_employment_contracts set contract_type=p_employment_type,pay_basis=p_pay_basis,pay_frequency=p_pay_basis where id=active_contract;
 end if;
 update payroll_profiles set ssnit_number=nullif(p_ssnit_number,''),tax_number=nullif(p_tax_number,''),bank_name=nullif(p_bank_name,''),bank_branch=nullif(p_bank_branch,''),bank_account_name=nullif(p_bank_account_name,''),bank_account_number=nullif(p_bank_account_number,''),payment_method=coalesce(nullif(p_payment_method,''),'bank'),momo_network=nullif(p_momo_network,''),momo_number=nullif(p_momo_number,'') where employee_id=p_employee and tenant_id=p_tenant;
 if p_basic_salary is not null and p_basic_salary<>old_salary then
   insert into hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by) values(p_tenant,p_employee,old_salary,p_basic_salary,case when old_salary=0 then 'initial' else 'manual' end,'Employee Master compensation update',coalesce(p_salary_effective,current_date),auth.uid(),auth.uid());
   if active_contract is not null and coalesce(p_salary_effective,current_date)<=current_date then update hr_employment_contracts set basic_salary=p_basic_salary where id=active_contract; end if;
 end if;
 insert into hr_employment_events(tenant_id,employee_id,event_type,effective_date,title,details,created_by) values(p_tenant,p_employee,'profile_update',current_date,'Employee master updated',jsonb_build_object('department_id',p_department,'position_id',p_position,'pay_basis',p_pay_basis,'salary_effective',p_salary_effective),auth.uid());
 result:=jsonb_build_object('ok',true,'old_salary',old_salary,'new_salary',p_basic_salary,'pay_basis',p_pay_basis); return result;
end $$;
grant execute on function public.hr_update_employee_master(uuid,uuid,text,text,text,text,date,text,text,text,text,text,uuid,uuid,text,text,text,numeric,date,text,text,text,text,text,text,text,text,text) to authenticated;
