import {supabase} from "../lib/supabase";
const wrap=async p=>{try{const {data,error}=await p;return {data,error}}catch(error){return {data:null,error}}};
export const loadNextRegistrationReadiness=(studentId=null)=>wrap(supabase.rpc("unimis_next_registration_readiness",{p_student_id:studentId||null}));
