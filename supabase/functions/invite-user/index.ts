import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({ok:false,error:"POST required"},405);
 try{
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!anon||!service)throw new Error("Required Supabase runtime environment variables are missing.");
  const authorization=req.headers.get("Authorization");if(!authorization)return json({ok:false,error:"Authentication required"},401);
  const caller=createClient(url,anon,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:auth,error:authError}=await caller.auth.getUser();if(authError||!auth.user)return json({ok:false,error:"Invalid user session"},401);
  const body=await req.json();if(!body.institution_id)throw new Error("institution_id is required");
  if(body.platform_owner===true){
   const {data:record,error:prepareError}=await caller.schema("unimis").rpc("unimis_prepare_platform_owner156",{p_inst:body.institution_id});
   if(prepareError)throw prepareError;if(!record?.email||!record?.role_id)throw new Error("Pending institution Owner not found");
   const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
   const options:{data:Record<string,unknown>;redirectTo?:string}={data:{platform_owner:true,institution_id:record.institution_id,role_id:record.role_id,first_name:record.first_name,last_name:record.last_name,app_id:"unimis"}};
   if(body.redirect_to)options.redirectTo=String(body.redirect_to);
   const {data,error}=await admin.auth.admin.inviteUserByEmail(record.email,options);if(error)throw error;
   if(!data.user)throw new Error("Auth did not return the invited Owner");
   return json({ok:true,platform_owner:true,auth_user_id:data.user.id,email:record.email});
  }
  let invite=body.invitation_id;
  if(!invite){
   const {data,error}=await caller.rpc("create_user_invitation",{p_institution_id:body.institution_id,p_email:body.email,p_role_id:body.role_id,p_first_name:body.first_name||null,p_middle_name:body.middle_name||null,p_last_name:body.last_name||null});
   if(error)throw error;invite=data?.id;if(!invite)throw new Error("Approved invitation was not found");
  }
  // Never use request-supplied role/email in Auth metadata. Canonical invitation is checked as caller.
  const {data:record,error:prepareError}=await caller.rpc("unimis_prepare_invitation116",{p_inst:body.institution_id,p_invitation:invite});
  if(prepareError)throw prepareError;
  if(!record)throw new Error("Pending invitation not found");
  if(body.role_id&&body.role_id!==record.role_id||body.email&&String(body.email).trim().toLowerCase()!==record.email.toLowerCase())throw new Error("Request does not match the approved invitation");
  const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const options:{data:Record<string,unknown>;redirectTo?:string}={data:{institution_id:record.institution_id,role_id:record.role_id,invitation_id:record.id,first_name:record.first_name,middle_name:record.middle_name,last_name:record.last_name,staff_number:record.staff_number,student_number:record.student_number}};
  if(body.redirect_to)options.redirectTo=String(body.redirect_to);
  const {data,error}=await admin.auth.admin.inviteUserByEmail(record.email,options);if(error)throw error;
  if(!data.user)throw new Error("Auth did not return the invited user");
  return json({ok:true,invitation_id:record.id,auth_user_id:data.user.id,email:record.email});
 }catch(e){return json({ok:false,error:e instanceof Error?e.message:String((e as {message?:string})?.message||e)},400)}
});


