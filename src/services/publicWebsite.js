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
