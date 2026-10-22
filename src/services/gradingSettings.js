import {supabase} from "../lib/supabase";
const wrap=({data,error})=>({data,error});
export const loadGradingSettings=async()=>wrap(await supabase.rpc("unimis_grading_settings"));
export const saveGradingScheme=async scheme=>wrap(await supabase.rpc("unimis_save_grading_scheme",{p_scheme:scheme}));
export const saveGradingAssignment=async assignment=>wrap(await supabase.rpc("unimis_save_grading_assignment",{p_assignment:assignment}));
export const deleteGradingAssignment=async id=>wrap(await supabase.rpc("unimis_delete_grading_assignment",{p_assignment_id:id}));
