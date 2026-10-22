import {supabase} from "../lib/supabase";
const wrap=(r)=>r.error?{data:null,error:r.error}:{data:r.data,error:null};
export async function loadRegistrationWorkspace(){return wrap(await supabase.rpc("unimis_student_registration_workspace"));}
export async function saveCourseSelection(periodRegistrationId,courseOfferingIds){return wrap(await supabase.rpc("unimis_save_student_course_selection",{p_period_registration_id:periodRegistrationId,p_course_offering_ids:courseOfferingIds}));}
export async function submitRegistration(periodRegistrationId){return wrap(await supabase.rpc("unimis_submit_student_registration",{p_period_registration_id:periodRegistrationId}));}
export async function loadRegistrationApprovalQueue(institutionId){return wrap(await supabase.rpc("unimis_registration_approval_queue",{p_institution_id:institutionId}));}
export async function decideRegistration(periodRegistrationId,action,notes=null){return wrap(await supabase.rpc("unimis_decide_student_registration",{p_period_registration_id:periodRegistrationId,p_action:action,p_notes:notes}));}
export async function loadRegistrationSlip(periodRegistrationId){return wrap(await supabase.rpc("unimis_registration_slip",{p_period_registration_id:periodRegistrationId}));}

export async function loadRegistrationHistory(){return wrap(await supabase.rpc("unimis_student_registration_history"));}
