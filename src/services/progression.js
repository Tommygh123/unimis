import {supabase} from "../lib/supabase";
const wrap=async p=>{try{const {data,error}=await p;return {data,error}}catch(error){return {data:null,error}}};
export const evaluateProgression=(academicYearId,programmeId=null,level=null)=>wrap(supabase.rpc("unimis_progression_evaluate",{p_academic_year_id:academicYearId,p_programme_id:programmeId||null,p_level:level?Number(level):null}));
export const loadProgressionQueue=(academicYearId=null,programmeId=null,level=null,decision=null)=>wrap(supabase.rpc("unimis_progression_queue",{p_academic_year_id:academicYearId||null,p_programme_id:programmeId||null,p_level:level?Number(level):null,p_decision:decision||null}));
export const bulkPromote=(ids)=>wrap(supabase.rpc("unimis_progression_bulk_promote",{p_review_ids:ids}));
export const overrideProgression=(id,decision,reason)=>wrap(supabase.rpc("unimis_progression_override",{p_review_id:id,p_decision:decision,p_reason:reason}));

export const finalizeProgressionException=(id,decision,reason)=>wrap(supabase.rpc("unimis_progression_finalize_exception",{p_review_id:id,p_decision:decision,p_reason:reason}));
