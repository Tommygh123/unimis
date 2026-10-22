create or replace function pg_temp.source_fingerprint117() returns text language plpgsql as $f$
declare source_inst uuid; t record; j jsonb; parts jsonb:='{}'::jsonb;
begin
 select id into source_inst from public.institutions where code='UNIMIS-DEMO-UNIV';
 if source_inst is null then raise exception 'Source school not found'; end if;
 for t in select c.table_name from information_schema.columns c join information_schema.tables it on it.table_schema=c.table_schema and it.table_name=c.table_name where c.table_schema='public' and c.column_name='institution_id' and it.table_type='BASE TABLE' order by c.table_name loop
  execute format('select coalesce(jsonb_agg(j order by j::text),''[]''::jsonb) from (select to_jsonb(x) j from public.%I x where institution_id=$1) q',t.table_name) into j using source_inst;
  parts:=parts||jsonb_build_object(t.table_name,j);
 end loop;
 parts:=parts||jsonb_build_object('institution',(select to_jsonb(i) from public.institutions i where id=source_inst));
 return md5(parts::text);
end $f$;
select pg_temp.source_fingerprint117();
