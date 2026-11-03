import {supabase} from "../lib/supabase";
const wrap=async p=>{try{const {data,error}=await p;return {data,error}}catch(error){return {data:null,error}}};
export const loadReviewFilters=()=>wrap(supabase.rpc("unimis_exams_review_filters"));
export const loadReviewQueue=f=>wrap(supabase.rpc("unimis_exams_review_queue",{p_academic_year_id:f.year||null,p_academic_period_id:f.period||null,p_faculty_id:f.faculty||null,p_department_id:f.department||null,p_programme_id:f.programme||null,p_level:f.level?Number(f.level):null,p_status:f.status||null,p_exceptions_only:!!f.exceptionsOnly}));
export const bulkApproveResults=(ids,note=null)=>wrap(supabase.rpc("unimis_bulk_approve_course_results",{p_course_offering_ids:ids,p_note:note}));
