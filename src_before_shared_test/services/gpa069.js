import {supabase} from "../lib/supabase";
export async function loadStudentGpaSummary(){try{const {data,error}=await supabase.rpc("unimis_student_gpa_summary");return {data,error}}catch(error){return {data:null,error}}}
