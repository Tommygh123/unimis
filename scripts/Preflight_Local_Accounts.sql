DO $$
DECLARE inst uuid;
BEGIN
 SELECT id INTO inst FROM public.institutions WHERE code='UNIMIS-DEMO-UNIV' AND status='active';
 IF inst IS NULL THEN RAISE EXCEPTION 'Active UniMIS Demo University not found'; END IF;
 IF EXISTS(SELECT 1 FROM public.institution_users m JOIN public.roles r ON r.id=m.role_id JOIN auth.users u ON u.id=m.user_id WHERE m.institution_id=inst AND r.code='owner' AND m.status='active' AND lower(u.email)<>'kk@gmail.com') THEN RAISE EXCEPTION 'Another active Owner exists; use the normal approval process'; END IF;
 IF (SELECT count(*) FROM public.roles WHERE institution_id=inst AND code IN ('owner','registrar') AND is_active)<>2 THEN RAISE EXCEPTION 'Expected active Owner and Registrar roles for this school'; END IF;
 IF EXISTS(SELECT 1 FROM public.institution_users m JOIN auth.users u ON u.id=m.user_id JOIN public.roles r ON r.id=m.role_id WHERE lower(u.email) IN ('kk@gmail.com','pp@gmail.com') AND (m.institution_id<>inst OR r.code<>CASE WHEN lower(u.email)='kk@gmail.com' THEN 'owner' ELSE 'registrar' END OR m.status<>'active')) THEN RAISE EXCEPTION 'Existing account has different membership or inactive status; no roles changed'; END IF;
 IF EXISTS(SELECT 1 FROM public.unimis_additional_roles116 a JOIN public.institution_users m ON m.id=a.institution_user_id JOIN auth.users u ON u.id=m.user_id WHERE lower(u.email) IN ('kk@gmail.com','pp@gmail.com')) THEN RAISE EXCEPTION 'Additional roles already exist; use the normal approval process'; END IF;
 IF EXISTS(SELECT 1 FROM public.unimis_platform_operators116 op JOIN auth.users u ON u.id=op.user_id WHERE op.active AND lower(u.email) IN ('kk@gmail.com','pp@gmail.com')) THEN RAISE EXCEPTION 'Technical operator accounts cannot become school accounts'; END IF;
END $$;
