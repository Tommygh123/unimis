import {supabase} from "./supabase";
const STAFF_ROLES=new Set(["owner","auditor","admin","registrar","admissions_officer","finance_officer","hr_officer","payroll_officer","exam_officer","librarian","accommodation_officer","communications_officer","lecturer","staff"]);
export async function classifyPortalAccount(user){
 if(!user)return {kind:"guest",roles:[],memberships:[],applicant:null};
 const [m,a,operator]=await Promise.all([
  supabase.rpc("unimis_my_portal_memberships118"),
  supabase.from("applicants").select("id,institution_id,user_id,first_name,last_name").eq("user_id",user.id).maybeSingle(),
  supabase.rpc("unimis_is_platform_operator116")
 ]);
 const memberships=m.error?[]:(m.data||[]),roles=memberships.filter(x=>x.role?.is_active!==false).map(x=>x.role?.code).filter(Boolean),applicant=a.error?null:(a.data||null),mt=String(user.user_metadata?.account_type||"").toLowerCase();
 if(operator.data===true)return {kind:"staff",roles:["platform_superadmin"],memberships:[],applicant:null};
 if(m.error)return {kind:"lookup_error",roles:[],memberships:[],applicant:null,error:m.error};
 if(roles.some(r=>STAFF_ROLES.has(r)))return {kind:"staff",roles,memberships,applicant};
 if(roles.includes("student"))return {kind:"student",roles,memberships,applicant};
 if(roles.includes("parent"))return {kind:"parent",roles,memberships,applicant};
 if(applicant||mt==="applicant")return {kind:"applicant",roles,memberships,applicant};
 return {kind:"unknown",roles,memberships,applicant};
}
export function portalMismatchMessage(kind,target){
 if(kind==="lookup_error")return "Your account signed in, but its assigned roles could not be loaded. Apply the portal login update, then reload and try again.";
 if(target==="staff"){if(kind==="applicant")return "Applicant account detected. Use the Applicant Portal.";if(kind==="student")return "Student account detected. Use the Student Portal.";return "This account is not authorised for the Staff & Lecturer Portal.";}
 if(target==="student"){if(kind==="staff")return "Staff account detected. Use the Staff & Lecturer Portal.";if(kind==="applicant")return "Applicant account detected. Use the Applicant Portal until student conversion is complete.";return "This account is not authorised for the Student Portal.";}
 if(target==="applicant"){if(kind==="staff")return "University staff account detected. Staff accounts cannot create applicant records. Use the Staff & Lecturer Portal.";if(kind==="student")return "Student account detected. Use the Student Portal.";if(kind==="parent")return "Parent account detected. This account cannot create an admission application.";return "This account is not authorised for the Applicant Portal.";}
 return "This account cannot use this portal.";
}
