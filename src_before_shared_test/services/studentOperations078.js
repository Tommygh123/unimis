import {supabase} from "../lib/supabase";
const wrap=({data,error})=>({data,error});
export const loadStudentManagementFilters=async()=>wrap(await supabase.rpc("unimis_student_management_filters"));
export const loadStudentProfile=async id=>wrap(await supabase.rpc("unimis_student_profile",{p_student_id:id}));
