import {supabase} from "../lib/supabase";
const wrap=async p=>{try{const {data,error}=await p;return {data,error}}catch(error){return {data:null,error}}};
export const loadDegreeClassificationSettings=()=>wrap(supabase.rpc("unimis_degree_classification_settings"));
export const saveDegreeClassificationScheme=scheme=>wrap(supabase.rpc("unimis_save_degree_classification_scheme",{p_scheme:scheme}));
export const assignDegreeClassification=(programmeId,schemeId)=>wrap(supabase.rpc("unimis_assign_degree_classification",{p_programme_id:programmeId,p_scheme_id:schemeId}));
export const loadStandardDegreeClassification=()=>wrap(supabase.rpc("unimis_load_standard_degree_classification"));
