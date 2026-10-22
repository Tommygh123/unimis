import {supabase} from "../lib/supabase";
const wrap=({data,error})=>({data,error});
export const loadProgressionRuleSettings=async()=>wrap(await supabase.rpc("unimis_progression_rule_settings"));
export const saveProgressionRule=async rule=>wrap(await supabase.rpc("unimis_save_progression_rule",{p_rule:rule}));
export const deleteProgressionRule=async id=>wrap(await supabase.rpc("unimis_delete_progression_rule",{p_rule_id:id}));
