import {supabase} from "../lib/supabase";
const wrap=async p=>{try{const {data,error}=await p;return {data,error}}catch(error){return {data:null,error}}};
export const syncTrails=(year=null)=>wrap(supabase.rpc("unimis_sync_academic_trails",{p_academic_year_id:year||null}));
export const loadTrails=(programme=null,level=null,status=null)=>wrap(supabase.rpc("unimis_trail_students",{p_programme_id:programme||null,p_level:level?Number(level):null,p_status:status||null}));
export const evaluateGraduation=(year,programme=null)=>wrap(supabase.rpc("unimis_evaluate_graduation",{p_academic_year_id:year,p_programme_id:programme||null}));
export const loadGraduation=(year=null,programme=null,decision=null)=>wrap(supabase.rpc("unimis_graduation_queue",{p_academic_year_id:year||null,p_programme_id:programme||null,p_decision:decision||null}));
export const approveGraduation=ids=>wrap(supabase.rpc("unimis_approve_graduation",{p_review_ids:ids}));
export const markGraduated=(ids,date)=>wrap(supabase.rpc("unimis_mark_graduated",{p_review_ids:ids,p_graduation_date:date}));
