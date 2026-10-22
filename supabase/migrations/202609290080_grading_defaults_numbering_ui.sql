begin;

-- 080: Make department/faculty/year/sequence the preferred student-number format.
-- Existing students and numbers are NOT changed.
create or replace function public.unimis_student_numbering_preview(p_institution_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_settings jsonb; v_prefix text; v_digits int; v_sep text; v_year bool;
begin
 select settings into v_settings from public.institutions where id=p_institution_id;
 v_prefix:=coalesce(v_settings#>>'{student_numbering,prefix}','');
 v_digits:=coalesce((v_settings#>>'{student_numbering,digits}')::int,3);
 v_sep:=coalesce(v_settings#>>'{student_numbering,separator}','/');
 v_year:=coalesce((v_settings#>>'{student_numbering,include_year}')::boolean,true);
 return jsonb_build_object(
   'legacy_prefix',v_prefix,'digits',v_digits,'separator',v_sep,'include_year',v_year,
   'recommended_format','FACULTY/DEPARTMENT/YY/NNN',
   'example','FET/ECE/26/001',
   'note','The current department-based generator is preferred. Legacy STU prefix is retained only for compatibility.'
 );
end $$;
grant execute on function public.unimis_student_numbering_preview(uuid) to authenticated;
notify pgrst,'reload schema';
commit;