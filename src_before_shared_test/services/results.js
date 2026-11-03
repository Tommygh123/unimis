import {supabase} from "../lib/supabase";
const wrap=r=>r;
export async function lecturerResultPreview(id){return wrap(await supabase.rpc("unimis_lecturer_result_preview",{p_course_offering_id:id}));}
export async function submitCourseResults(id){return wrap(await supabase.rpc("unimis_submit_course_results",{p_course_offering_id:id}));}
export async function adminResultsQueue(){return wrap(await supabase.rpc("unimis_results_admin_queue"));}
export async function adminCourseResults(id){return wrap(await supabase.rpc("unimis_admin_course_results",{p_course_offering_id:id}));}
export async function adminResultAction(id,action,notes=""){return wrap(await supabase.rpc("unimis_admin_result_action",{p_course_offering_id:id,p_action:action,p_notes:notes||null}));}
export async function studentPublishedResults(){return wrap(await supabase.rpc("unimis_student_published_results"));}

export async function lecturerResultAnalytics(id){return wrap(await supabase.rpc("unimis_lecturer_result_analytics",{p_course_offering_id:id}));}
export async function adminResultAnalytics(id){return wrap(await supabase.rpc("unimis_admin_result_analytics",{p_course_offering_id:id}));}
