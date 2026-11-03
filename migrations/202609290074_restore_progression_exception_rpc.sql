begin;
drop function if exists public.unimis_progression_finalize_exception(uuid,text,text);
create function public.unimis_progression_finalize_exception(p_review_id uuid,p_decision text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; r record;
begin
 v_inst:=public.unimis_progression_access();
 if v_inst is null then raise exception 'Progression access required'; end if;
 if p_decision not in ('repeat','probation','deferred','withdrawn') then raise exception 'Invalid final exception decision'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Decision reason is required'; end if;
 select * into r from public.student_progression_reviews where id=p_review_id and institution_id=v_inst for update;
 if r.id is null then raise exception 'Progression review not found'; end if;
 if r.decision not in ('manual_review','repeat','probation','deferred','withdrawn') then raise exception 'Only exception cases can be finalized here'; end if;
 update public.student_progression_reviews set decision=p_decision,override_reason=p_reason,updated_at=now() where id=r.id;
 insert into public.student_progression_history(institution_id,student_id,academic_year_id,programme_enrolment_id,from_level,to_level,action,system_decision,reasons,notes,acted_by)
 values(v_inst,r.student_id,r.academic_year_id,r.programme_enrolment_id,r.from_level,r.from_level,'exception_finalized',r.decision,r.reasons,p_reason,auth.uid());
 return jsonb_build_object('ok',true,'review_id',r.id,'decision',p_decision,'student_id',r.student_id,'level',r.from_level);
end $$;
revoke all on function public.unimis_progression_finalize_exception(uuid,text,text) from public;
grant execute on function public.unimis_progression_finalize_exception(uuid,text,text) to authenticated;
notify pgrst, 'reload schema';
commit;
