import {supabase} from "../lib/supabase";

const result=(r)=>r.error?{data:null,error:r.error}:{data:r.data,error:null};

export async function loadStudentLifecycleSettings(institutionId){
  return result(await supabase.rpc("unimis_student_lifecycle_settings",{p_institution_id:institutionId}));
}
export async function saveStudentLifecycleSettings(institutionId,settings){
  return result(await supabase.rpc("unimis_update_student_lifecycle_settings",{p_institution_id:institutionId,p_settings:settings}));
}
export async function loadStudentConversionQueue(institutionId){
  return result(await supabase.rpc("unimis_student_conversion_queue",{p_institution_id:institutionId}));
}
export async function loadStudentsDirectory(institutionId){
  return result(await supabase.rpc("unimis_students_directory",{p_institution_id:institutionId}));
}
export async function convertAcceptedApplication(applicationId){
  return result(await supabase.rpc("unimis_convert_accepted_application_to_student",{p_application_id:applicationId}));
}
export async function generateInitialInvoice(studentId){
  return result(await supabase.rpc("unimis_generate_student_initial_invoice",{p_student_id:studentId}));
}
export async function loadStudentPortalDashboard(){
  return result(await supabase.rpc("unimis_student_portal_dashboard"));
}

export async function loadStudentGraduationStatus(){
  return result(await supabase.rpc("unimis_student_graduation_status"));
}

export async function loadStudentAcademicStanding(){
  return result(await supabase.rpc("unimis_student_academic_standing"));
}
