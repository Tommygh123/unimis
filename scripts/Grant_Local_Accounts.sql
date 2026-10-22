BEGIN;
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
DO $$
DECLARE inst uuid; rec record; uid uuid; rid uuid; member uuid;
BEGIN
 SELECT id INTO inst FROM public.institutions WHERE code='UNIMIS-DEMO-UNIV';
 FOR rec IN SELECT * FROM (VALUES ('kk@gmail.com','owner','School Owner'),('pp@gmail.com','registrar','School Registrar')) x(email,role_code,display_name) LOOP
  SELECT id INTO uid FROM auth.users WHERE lower(email)=rec.email AND email_confirmed_at IS NOT NULL;
  IF uid IS NULL THEN RAISE EXCEPTION 'Confirmed Auth account missing: %',rec.email; END IF;
  SELECT id INTO rid FROM public.roles WHERE institution_id=inst AND code=rec.role_code AND is_active;
  INSERT INTO public.profiles(id,display_name,status) VALUES(uid,rec.display_name,'active') ON CONFLICT(id) DO NOTHING;
  SELECT id INTO member FROM public.institution_users WHERE institution_id=inst AND user_id=uid;
  IF member IS NULL THEN
   INSERT INTO public.institution_users(institution_id,user_id,role_id,status,is_primary) VALUES(inst,uid,rid,'active',true) RETURNING id INTO member;
   INSERT INTO public.audit_logs(institution_id,action,entity_type,entity_id,new_data,metadata)
   VALUES(inst,'local_reconstruction_initial_membership','institution_users',member,jsonb_build_object('email',rec.email,'role',rec.role_code),jsonb_build_object('actor','local_postgres_recovery_operator','setup','accounts155'));
  END IF;
 END LOOP;
END $$;
COMMIT;
SELECT u.email,i.name AS school,r.code AS role,m.status FROM public.institution_users m JOIN auth.users u ON u.id=m.user_id JOIN public.roles r ON r.id=m.role_id JOIN public.institutions i ON i.id=m.institution_id WHERE lower(u.email) IN ('kk@gmail.com','pp@gmail.com') ORDER BY r.code;
