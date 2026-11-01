import { supabase } from "../lib/supabase";
const DOCUMENT_BUCKET = "admission-documents";
const err = e => e ? (e instanceof Error ? e : new Error(e.message || "Something went wrong.")) : null;

export async function loadApplicantPortalBootstrap(){
  const {data,error}=await supabase.rpc("unimis_admissions_public_bootstrap");
  return {data:data||null,error:err(error)};
}
export async function loadApplicantDashboard(){
  const {data,error}=await supabase.rpc("unimis_applicant_dashboard");
  if(error)return {data:null,error:err(error)};

  // New dashboard RPC embeds subject_results inside each qualification.
  // Flatten them only as a backward-compatible convenience for older UI code.
  const applications=data?.applications||[];
  const applicationIds=applications.map(a=>a.id).filter(Boolean);
  let offers=[];
  if(applicationIds.length){
    const offerResult=await supabase
      .from("admission_offers")
      .select("*,programme:programmes(id,name,code,award_type)")
      .in("application_id",applicationIds)
      .order("created_at",{ascending:false});
    if(!offerResult.error)offers=offerResult.data||[];
  }
  const applicationsWithOffers=applications.map(app=>{
    const own=offers.filter(o=>o.application_id===app.id);
    return {...app,offers:own.length?own:(app.offers||[])};
  });
  const embedded=(data?.qualifications||[]).flatMap(q=>
    (Array.isArray(q.subject_results)?q.subject_results:[]).map(r=>({
      ...r,
      qualification_id:r.qualification_id||q.id
    }))
  );
  if(embedded.length)return {data:{...(data||{}),applications:applicationsWithOffers,offers,subject_results:embedded},error:null};

  // Compatibility fallback while older local databases are being migrated.
  const applicantId=data?.applicant?.id;
  if(!applicantId)return {data:data||null,error:null};
  const subjectResults=await supabase
    .from("applicant_subject_results")
    .select("*")
    .eq("applicant_id",applicantId)
    .order("created_at",{ascending:true});
  if(subjectResults.error)return {data:null,error:err(subjectResults.error)};
  return {data:{...(data||{}),applications:applicationsWithOffers,offers,subject_results:subjectResults.data||[]},error:null};
}
export async function saveApplicantPortalProfile(v){
  const {data,error}=await supabase.rpc("unimis_applicant_save_profile",{
    p_institution_id:v.institution_id,p_first_name:v.first_name,p_middle_name:v.middle_name||null,
    p_last_name:v.last_name,p_date_of_birth:v.date_of_birth||null,p_gender:v.gender||null,
    p_phone:v.phone||null,p_nationality:v.nationality||null,
    p_country_of_residence:v.country_of_residence||null,p_address:v.address||null,
    p_city:v.city||null,p_region:v.region||null,p_applicant_category:v.applicant_category,
    p_national_id_type:v.national_id_type||null,p_national_id_number:v.national_id_number||null,
    p_passport_number:v.passport_number||null,p_passport_expiry_date:v.passport_expiry_date||null,
    p_country_of_birth:v.country_of_birth||null,p_residency_status:v.residency_status||null
  });
  return {data,error:err(error)};
}
export async function createApplicantApplication({admissionCycleId,programmeIds,entryType="regular",notes=null}){
  const {data,error}=await supabase.rpc("unimis_applicant_create_application",{
    p_admission_cycle_id:admissionCycleId,p_programme_ids:programmeIds,
    p_entry_type:entryType,p_notes:notes
  });
  return {data,error:err(error)};
}

export async function addApplicantExamQualification(v){
  const subjectResults=(v.subject_results||[])
    .filter(r=>r.subject?.trim()&&r.grade)
    .map(r=>({subject:r.subject.trim(),grade:r.grade,is_core:Boolean(r.is_core)}));
  const {data,error}=await supabase.rpc("unimis_applicant_add_exam_qualification",{
    p_qualification_type:v.qualification_type||"WASSCE",
    p_institution_name:v.institution_name||null,
    p_examining_body:v.examining_body||"WAEC",
    p_index_number:v.index_number||null,
    p_exam_year:v.completion_year?Number(v.completion_year):null,
    p_exam_sitting:v.exam_sitting||null,
    p_subject_results:subjectResults
  });
  return {data,error:err(error)};
}

export async function addApplicantQualification(v){
  const details=v.subject_results?.trim()?{...(v.details||{}),subject_results:v.subject_results.trim()}:(v.details||{});
  const {data,error}=await supabase.rpc("unimis_applicant_add_qualification",{
    p_qualification_type:v.qualification_type,p_institution_name:v.institution_name||null,
    p_examining_body:v.examining_body||null,p_index_number:v.index_number||null,
    p_completion_year:v.completion_year?Number(v.completion_year):null,
    p_overall_result:v.overall_result||null,p_details:details
  });
  return {data,error:err(error)};
}
export async function uploadApplicantDocument({institutionId,applicationId,documentType,file,replaceDocument=null}){
 try{
  if(!file)return {data:null,error:new Error("Choose a file to upload.")};
  const types={pdf:"application/pdf",jpg:"image/jpeg",jpeg:"image/jpeg",png:"image/png",webp:"image/webp"};
  const mime=types[file.name.split('.').pop().toLowerCase()];
  if(!mime||file.size<=0||file.size>10*1024*1024)return {data:null,error:new Error("Choose a PDF, JPG, PNG or WebP file up to 10 MB.")};
  const safe=file.name.replace(/[^a-zA-Z0-9._-]+/g,"-").replace(/-+/g,"-");
  const path=`${institutionId}/${applicationId}/${crypto.randomUUID()}-${safe}`;
  const upload=await supabase.storage.from(DOCUMENT_BUCKET).upload(path,file,{cacheControl:"3600",upsert:false,contentType:mime});
  if(upload.error)return {data:null,error:new Error(/42P10/.test(upload.error.message||"")?"Upload failed: Local Storage is missing a matching database index. Apply the UniMIS Storage repair migration, then retry.":`Upload failed: ${upload.error.message}. Please retry, or contact your admissions office if the problem continues.`)};
  const {data,error}=await supabase.rpc("unimis_applicant_save_document",{p_application_id:applicationId,p_document_type:documentType,p_file_name:file.name,p_storage_path:path,p_mime_type:mime,p_file_size_bytes:file.size,p_replace_document_id:replaceDocument?.id||null});
  if(error){await supabase.storage.from(DOCUMENT_BUCKET).remove([path]);return {data:null,error:err(error)}}
  // The original stays intact until the new object and its metadata are saved.
  if(replaceDocument?.storage_path)await supabase.storage.from(DOCUMENT_BUCKET).remove([replaceDocument.storage_path]);
  return {data,error:null};
 }catch(error){return {data:null,error:err(error)}}
}
export async function previewApplicantDocument(path){const {data,error}=await supabase.storage.from(DOCUMENT_BUCKET).createSignedUrl(path,300);if(error)return {data:null,error:err(error)};return {data:data.signedUrl,error:null}}
export async function submitApplicantApplication(applicationId){
  const {data,error}=await supabase.rpc("submit_admission_application",{p_application_id:applicationId});
  return {data,error:err(error)};
}
export async function initializeApplicantPaystackPayment(applicationId){
  const {data,error}=await supabase.functions.invoke("initialize-admission-payment",{
    body:{application_id:applicationId,callback_url:`${window.location.origin}/apply?payment=callback`}
  });
  if(!error&&data?.ok===false)return {data:null,error:new Error(data.error||"Payment initialization failed.")};
  return {data,error:err(error)};
}
export async function verifyApplicantPaystackPayment(reference){
  const {data,error}=await supabase.functions.invoke("verify-admission-payment",{body:{reference}});
  if(!error&&data?.ok===false)return {data:null,error:new Error(data.error||"Payment verification failed.")};
  return {data,error:err(error)};
}
export async function respondToApplicantOffer(offerId,response,notes=null){
  const {data,error}=await supabase.rpc("unimis_applicant_respond_to_offer",{
    p_offer_id:offerId,p_response:response,p_notes:notes
  });
  return {data,error:err(error)};
}


export async function updateApplicantApplicationChoices(applicationId,programmeIds){
  const {data,error}=await supabase.rpc("unimis_applicant_update_application_choices",{
    p_application_id:applicationId,p_programme_ids:programmeIds
  });
  return {data,error:err(error)};
}

export async function updateApplicantExamQualification(v){
  const subjectResults=(v.subject_results||[])
    .filter(r=>r.subject?.trim()&&r.grade)
    .map(r=>({subject:r.subject.trim(),grade:r.grade,is_core:Boolean(r.is_core)}));
  const {data,error}=await supabase.rpc("unimis_applicant_update_exam_qualification",{
    p_qualification_id:v.id,
    p_qualification_type:v.qualification_type||"WASSCE",
    p_institution_name:v.institution_name||null,
    p_examining_body:v.examining_body||"WAEC",
    p_index_number:v.index_number||null,
    p_exam_year:v.completion_year?Number(v.completion_year):null,
    p_exam_sitting:v.exam_sitting||null,
    p_subject_results:subjectResults
  });
  return {data,error:err(error)};
}
export async function updateApplicantQualification(v){
  const details=v.subject_results?.trim()?{...(v.details||{}),subject_results:v.subject_results.trim()}:(v.details||{});
  const {data,error}=await supabase.rpc("unimis_applicant_update_qualification",{
    p_qualification_id:v.id,p_qualification_type:v.qualification_type,
    p_institution_name:v.institution_name||null,p_examining_body:v.examining_body||null,
    p_index_number:v.index_number||null,p_completion_year:v.completion_year?Number(v.completion_year):null,
    p_overall_result:v.overall_result||null,p_details:details
  });
  return {data,error:err(error)};
}
export async function deleteApplicantQualification(id){
  const {data,error}=await supabase.rpc("unimis_applicant_delete_qualification",{p_qualification_id:id});
  return {data,error:err(error)};
}
export async function deleteApplicantDocument(documentRow){
  // Remove the object while ownership metadata still exists, then remove metadata.
  if(documentRow?.storage_path){
    const removal=await supabase.storage.from(DOCUMENT_BUCKET).remove([documentRow.storage_path]);
    if(removal.error)return {data:null,error:err(removal.error)};
  }
  const {data,error}=await supabase.rpc("unimis_applicant_delete_document",{p_document_id:documentRow.id});
  return {data,error:err(error)};
}

export async function applicantSignUp({email,password,fullName}){
  const {data,error}=await supabase.auth.signUp({
    email,password,options:{
      data:{full_name:fullName,account_type:"applicant",app_id:"unimis"},
      emailRedirectTo:`${window.location.origin}/auth/callback?next=/apply`
    }
  });
  return {data,error:err(error)};
}
export async function applicantSignIn(email,password){
  const {data,error}=await supabase.auth.signInWithPassword({email,password});
  return {data,error:err(error)};
}
