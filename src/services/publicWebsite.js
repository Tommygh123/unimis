import { supabase } from "../lib/supabase";
const normalizeError=(error)=>error?new Error(error.message||"Request failed"):null;
export async function loadPublicWebsite(){const {data,error}=await supabase.rpc("unimis_public_website_bootstrap");return {data:data||{},error:normalizeError(error)};}
export async function loadWebsiteAdmin(){const {data,error}=await supabase.rpc("unimis_website_admin_bootstrap");return {data:data||{},error:normalizeError(error)};}
export async function saveWebsiteSettings(payload){const {data,error}=await supabase.rpc("unimis_save_website_settings",{p_payload:payload});return {data,error:normalizeError(error)};}
export async function saveWebsiteAnnouncement(id,payload){const {data,error}=await supabase.rpc("unimis_save_website_announcement",{p_id:id||null,p_payload:payload});return {data,error:normalizeError(error)};}
export async function deleteWebsiteAnnouncement(id){const {data,error}=await supabase.rpc("unimis_delete_website_announcement",{p_id:id});return {data,error:normalizeError(error)};}

export async function saveShowcaseItem(id,payload){const {data,error}=await supabase.rpc("unimis_save_showcase_item",{p_id:id||null,p_payload:payload});return {data,error:normalizeError(error)};}
export async function deleteShowcaseItem(id){const {data,error}=await supabase.rpc("unimis_delete_showcase_item",{p_id:id});return {data,error:normalizeError(error)};}
export async function saveProgrammePublication(programmeId,payload){const {data,error}=await supabase.rpc("unimis_save_programme_publication",{p_programme_id:programmeId,p_payload:payload});return {data,error:normalizeError(error)};}

export async function saveStaffPortalBranding(payload){const {data,error}=await supabase.rpc("unimis_save_staff_portal_branding",{p_payload:payload});return {data,error:normalizeError(error)};}


const WEBSITE_MEDIA_BUCKET="unimis-website-media";
export async function uploadWebsiteImage(institutionId,file,slot="content"){
 if(!institutionId)return {data:null,error:new Error("Institution is required for website media.")};
 if(!file?.type?.match(/^image\/(jpeg|png|webp)$/))return {data:null,error:new Error("Choose a JPG, PNG or WebP image.")};
 if(file.size>5*1024*1024)return {data:null,error:new Error("Image must be 5 MB or smaller.")};
 const ext=(file.name.split(".").pop()||"jpg").toLowerCase().replace(/[^a-z0-9]/g,"");
 const safeSlot=String(slot||"content").toLowerCase().replace(/[^a-z0-9_-]/g,"-");
 const path=`${institutionId}/${safeSlot}/${Date.now()}-${crypto.randomUUID()}.${ext}`;
 const {error}=await supabase.storage.from(WEBSITE_MEDIA_BUCKET).upload(path,file,{cacheControl:"3600",upsert:false,contentType:file.type});
 if(error)return {data:null,error:normalizeError(error)};
 const {data}=supabase.storage.from(WEBSITE_MEDIA_BUCKET).getPublicUrl(path);
 return {data:{path,publicUrl:data.publicUrl},error:null};
}


export async function uploadWebsiteVideo(institutionId,file,slot="showcase-video"){
 if(!institutionId)return {data:null,error:new Error("Institution is required for website media.")};
 if(!file?.type?.match(/^video\/(mp4|webm)$/))return {data:null,error:new Error("Choose an MP4 or WebM video.")};
 if(file.size>50*1024*1024)return {data:null,error:new Error("Video must be 50 MB or smaller.")};
 const ext=(file.name.split(".").pop()||"mp4").toLowerCase().replace(/[^a-z0-9]/g,"");
 const safeSlot=String(slot||"showcase-video").toLowerCase().replace(/[^a-z0-9_-]/g,"-");
 const path=`${institutionId}/${safeSlot}/${Date.now()}-${crypto.randomUUID()}.${ext}`;
 const {error}=await supabase.storage.from(WEBSITE_MEDIA_BUCKET).upload(path,file,{cacheControl:"3600",upsert:false,contentType:file.type});
 if(error)return {data:null,error:normalizeError(error)};
 const {data}=supabase.storage.from(WEBSITE_MEDIA_BUCKET).getPublicUrl(path);
 return {data:{path,publicUrl:data.publicUrl},error:null};
}
