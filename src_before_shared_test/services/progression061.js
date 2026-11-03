import {supabase} from "../lib/supabase";
const wrap=async p=>{try{const {data,error}=await p;return {data,error}}catch(error){return {data:null,error}}};

async function resolveInstitutionId(institutionId){
 if(institutionId)return {data:institutionId,error:null};
 const {data:{user},error:userError}=await supabase.auth.getUser();
 if(userError||!user)return {data:null,error:userError||new Error("Your session is not available. Please sign in again.")};
 const {data,error}=await supabase
  .from("institution_users")
  .select("institution_id")
  .eq("user_id",user.id)
  .eq("status","active")
  .order("is_primary",{ascending:false})
  .limit(1)
  .maybeSingle();
 if(error)return {data:null,error};
 if(!data?.institution_id)return {data:null,error:new Error("No active institution membership was found for this account.")};
 return {data:data.institution_id,error:null};
}

export async function loadProgressionFilters(institutionId=null){
 try{
  const resolved=await resolveInstitutionId(institutionId);
  if(resolved.error)return {data:null,error:resolved.error};
  const id=resolved.data;
  const [years,programmes]=await Promise.all([
   supabase.from("academic_years").select("*").eq("institution_id",id).order("start_date",{ascending:false}),
   supabase.from("programmes").select("id,code,name").eq("institution_id",id).order("name")
  ]);
  if(years.error||programmes.error)return {data:null,error:years.error||programmes.error};
  return {data:{academic_years:years.data||[],programmes:programmes.data||[]},error:null};
 }catch(error){return {data:null,error};}
}
export const loadStudentProgressionStatus=()=>wrap(supabase.rpc("unimis_student_progression_status"));
