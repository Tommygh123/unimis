-- 010b Complete PMS Evaluation Workflow
-- Adds controlled plan activation and separate self/supervisor assessment evidence.

alter table public.hr_performance_reviews add column if not exists plan_status text not null default 'planning';
alter table public.hr_performance_reviews drop constraint if exists hr_performance_reviews_plan_status_check;
alter table public.hr_performance_reviews add constraint hr_performance_reviews_plan_status_check check(plan_status in ('planning','activated','amended','closed'));
alter table public.hr_performance_reviews add column if not exists plan_activated_at timestamptz;
alter table public.hr_performance_reviews add column if not exists self_assessment_at timestamptz;
alter table public.hr_performance_reviews add column if not exists supervisor_assessment_at timestamptz;

alter table public.hr_performance_plan_items add column if not exists self_comments text;
alter table public.hr_performance_plan_items add column if not exists supervisor_comments text;

-- Existing 010 plans that already contain measures remain editable until deliberately activated.
update public.hr_performance_reviews r
set plan_status='planning'
where plan_status is null;

-- Recalculate each pillar using the employee plan's item weights, normalized inside the pillar.
-- This lets each industry/position have a different number of measures without distorting the 50/30/20 policy weights.
create or replace function public.hr_performance_recalculate(p_tenant uuid,p_review uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare a numeric:=0;b numeric:=0;c numeric:=0; wa numeric:=50;wb numeric:=30;wc numeric:=20; total numeric; rating text;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
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
 update hr_performance_reviews set target_output_score=round(a,2),responsibility_quality_score=round(b,2),professional_conduct_score=round(c,2),supervisor_score=total,final_score=total,final_rating=rating where tenant_id=p_tenant and id=p_review;
 return jsonb_build_object('target_output',round(a,2),'responsibility_quality',round(b,2),'professional_conduct',round(c,2),'final_score',total,'rating',rating);
end $$;
grant execute on function public.hr_performance_recalculate(uuid,uuid) to authenticated;
