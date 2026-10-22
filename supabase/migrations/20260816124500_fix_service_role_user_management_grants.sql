-- UniMIS: allow Edge Function service_role to access User Management tables/view

grant usage on schema public to service_role;

grant select, insert, update, delete
on table public.user_invitations
to service_role;

grant select
on table public.institution_user_directory
to service_role;

grant select, insert, update
on table public.profiles
to service_role;

grant select, insert, update
on table public.institution_users
to service_role;

grant select
on table public.roles
to service_role;

notify pgrst, 'reload schema';
