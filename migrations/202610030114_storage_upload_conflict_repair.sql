-- Legacy Storage repair applies only to its matching schema and owner privileges.
-- Modern Storage versions manage their own indexes. No ownership changes are made.
DO $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid='storage.objects'::regclass AND attname='archived_at' AND NOT attisdropped) THEN
  RAISE NOTICE 'Legacy archived-object index repair is not applicable to this Storage schema';
 ELSIF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_class c WHERE c.oid='storage.objects'::regclass AND pg_catalog.pg_has_role(current_user,c.relowner,'USAGE')) THEN
  RAISE NOTICE 'Legacy Storage index repair skipped: table owner privileges required';
 ELSE
  EXECUTE 'CREATE UNIQUE INDEX IF NOT EXISTS unimis_storage_upload_bucket_name_c_114 ON storage.objects(bucket_id,name COLLATE "C") WHERE archived_at IS NULL';
 END IF;
END $$;
