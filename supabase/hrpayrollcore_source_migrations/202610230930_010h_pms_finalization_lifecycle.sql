-- 010h PMS lifecycle: provisional scoring is distinct from approved/finalized results.
-- Existing historical completed appraisals are preserved as finalized. The controlled 2026 demo
-- reviews for Ama/Kwame are returned to pre-final state so the remaining workflow can be tested.

alter table public.hr_performance_reviews
  add column if not exists provisional_score numeric(6,2),
  add column if not exists provisional_rating text,
  add column if not exists finalization_status text not null default 'not_started',
  add column if not exists finalized_at timestamptz,
  add column if not exists finalized_by uuid;

do $$ begin
  if not exists(select 1 from pg_constraint where conname='hr_performance_reviews_finalization_status_check') then
    alter table public.hr_performance_reviews add constraint hr_performance_reviews_finalization_status_check
      check(finalization_status in ('not_started','pending_approval','finalized'));
  end if;
end $$;

-- Preserve genuinely completed historical records as finalized before changing calculation semantics.
update public.hr_performance_reviews
set provisional_score=coalesce(provisional_score,final_score),
    provisional_rating=coalesce(provisional_rating,final_rating),
    finalization_status='finalized',
    finalized_at=coalesce(finalized_at,completed_at,now())
where status='completed' and finalization_status<>'finalized';

-- Reviewed records may already contain a calculated score from the old engine. It is provisional.
update public.hr_performance_reviews
set provisional_score=coalesce(provisional_score,final_score),
    provisional_rating=coalesce(provisional_rating,final_rating),
    final_score=null,
    final_rating=null,
    finalization_status='not_started',
    finalized_at=null,
    finalized_by=null
where status<>'completed';

-- The controlled 2026 Kwame demo was marked completed only to demonstrate downstream data.
-- Return it to supervisor-reviewed state so final approval can be tested properly.
update public.hr_performance_reviews r
set status='reviewed', plan_status='activated', completed_at=null,
    provisional_score=coalesce(r.provisional_score,r.final_score),
    provisional_rating=coalesce(r.provisional_rating,r.final_rating),
    final_score=null, final_rating=null, finalization_status='not_started', finalized_at=null, finalized_by=null
from public.hr_employees e, public.hr_performance_cycles c, public.tenants t
where r.employee_id=e.id and r.cycle_id=c.id and r.tenant_id=t.id
  and e.employee_no='EMP002' and c.name='2026 Annual Performance Review' and t.code='TCC001';

create or replace function public.hr_performance_recalculate(p_tenant uuid,p_review uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare a numeric:=0;b numeric:=0;c numeric:=0; wa numeric:=50;wb numeric:=30;wc numeric:=20; total numeric; rating text; fin text;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select finalization_status into fin from hr_performance_reviews where tenant_id=p_tenant and id=p_review;
 if fin='finalized' then raise exception 'Finalized appraisal is locked'; end if;
 select coalesce(target_output_weight,50),coalesce(responsibility_quality_weight,30),coalesce(professional_conduct_weight,20)
 into wa,wb,wc from hr_performance_policies where tenant_id=p_tenant and active order by effective_from desc limit 1;

 select coalesce(sum(final_score*greatest(weight,0))/nullif(sum(greatest(weight,0)),0),avg(final_score),0) into a
 from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='target_output' and final_score is not null;
 select coalesce(sum(final_score*greatest(weight,0))/nullif(sum(greatest(weight,0)),0),avg(final_score),0) into b
 from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='responsibility_quality' and final_score is not null;
 select coalesce(sum(final_score*greatest(weight,0))/nullif(sum(greatest(weight,0)),0),avg(final_score),0) into c
 from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='professional_conduct' and final_score is not null;

 total:=round((a*wa+b*wb+c*wc)/nullif(wa+wb+wc,0),2);
 rating:=case when total>=90 then 'Exceptional' when total>=80 then 'Exceeds Expectations' when total>=65 then 'Meets Expectations' when total>=50 then 'Needs Improvement' else 'Unsatisfactory' end;
 update hr_performance_reviews set target_output_score=round(a,2),responsibility_quality_score=round(b,2),professional_conduct_score=round(c,2),supervisor_score=total,provisional_score=total,provisional_rating=rating,final_score=null,final_rating=null where tenant_id=p_tenant and id=p_review;
 return jsonb_build_object('target_output',round(a,2),'responsibility_quality',round(b,2),'professional_conduct',round(c,2),'provisional_score',total,'provisional_rating',rating);
end $$;

-- Database guard: finalized plan items cannot be silently changed or removed.
create or replace function public.hr_performance_guard_finalized_item() returns trigger language plpgsql set search_path=public as $$
declare rid uuid; fin text;
begin
 rid:=coalesce(new.review_id,old.review_id);
 select finalization_status into fin from hr_performance_reviews where id=rid;
 if fin='finalized' then raise exception 'Finalized appraisal is locked; use a controlled amendment workflow'; end if;
 return coalesce(new,old);
end $$;

drop trigger if exists trg_hr_performance_guard_finalized_item on public.hr_performance_plan_items;
create trigger trg_hr_performance_guard_finalized_item before update or delete on public.hr_performance_plan_items
for each row execute function public.hr_performance_guard_finalized_item();
