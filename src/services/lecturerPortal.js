import { supabase } from "../lib/supabase";
const wrap=({data,error})=>({data,error});
export async function loadLecturerWorkspace(){return wrap(await supabase.rpc("unimis_lecturer_workspace"));}
export async function loadLecturerClassList(courseOfferingId){return wrap(await supabase.rpc("unimis_lecturer_class_list",{p_course_offering_id:courseOfferingId}));}
export async function loadAttendanceSessions(courseOfferingId){return wrap(await supabase.rpc("unimis_lecturer_attendance_sessions",{p_course_offering_id:courseOfferingId}));}
export async function createAttendanceSession(courseOfferingId,form){return wrap(await supabase.rpc("unimis_create_attendance_session",{p_course_offering_id:courseOfferingId,p_session_date:form.session_date,p_start_time:form.start_time,p_end_time:form.end_time,p_topic:form.topic||null,p_venue:form.venue||null}));}
export async function loadAttendanceRegister(sessionId){return wrap(await supabase.rpc("unimis_attendance_register",{p_teaching_session_id:sessionId}));}
export async function saveAttendance(sessionId,records){return wrap(await supabase.rpc("unimis_save_attendance",{p_teaching_session_id:sessionId,p_records:records}));}

export async function loadLecturerAssessments(id){return wrap(await supabase.rpc("unimis_lecturer_assessments",{p_course_offering_id:id}));}
export async function createLecturerAssessment(id,f){return wrap(await supabase.rpc("unimis_create_assessment",{p_course_offering_id:id,p_name:f.name,p_assessment_type:f.assessment_type,p_max_score:Number(f.max_score),p_weight_percent:Number(f.weight_percent),p_due_date:f.due_date||null}));}
export async function loadAssessmentMarksheet(id){return wrap(await supabase.rpc("unimis_assessment_marksheet",{p_assessment_item_id:id}));}
export async function saveAssessmentScores(id,records){return wrap(await supabase.rpc("unimis_save_assessment_scores",{p_assessment_item_id:id,p_records:records}));}

export async function configureResultEntryMode(id,mode,caWeight=40,examWeight=60){return wrap(await supabase.rpc("unimis_configure_result_entry_mode",{p_course_offering_id:id,p_entry_mode:mode,p_ca_weight:Number(caWeight),p_exam_weight:Number(examWeight)}));}
export async function loadCaExamMarksheet(id){return wrap(await supabase.rpc("unimis_ca_exam_marksheet",{p_course_offering_id:id}));}
export async function saveCaExamScores(id,records){return wrap(await supabase.rpc("unimis_save_ca_exam_scores",{p_course_offering_id:id,p_records:records}));}
export async function loadLecturerReportingWorkspace(filters={}){try{return wrap(await supabase.rpc("unimis_lecturer_reporting_workspace",{p_filters:filters}))}catch(error){return {data:null,error}}}
