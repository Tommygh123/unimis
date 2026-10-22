begin;

grant select on table public.applicants to service_role;
grant select, update on table public.applications to service_role;
grant select, insert, update on table public.admission_application_payments to service_role;
grant select on table public.admission_fee_rules to service_role;
grant select on table public.admission_cycles to service_role;
grant select on table public.application_choices to service_role;
grant select on table public.programmes to service_role;
grant select on table public.application_documents to service_role;
grant select, update on table public.admission_offers to service_role;

grant execute on function public.unimis_get_application_fee(uuid) to service_role;

commit;
