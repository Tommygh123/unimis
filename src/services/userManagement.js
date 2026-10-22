import { supabase } from "../lib/supabase";

export async function listInstitutionUsers(institutionId) {
  return supabase
    .from("institution_user_directory")
    .select("*")
    .eq("institution_id", institutionId)
    .order("joined_at", { ascending: false });
}

export async function listInvitations(institutionId) {
  return supabase
    .from("user_invitations")
    .select("id,institution_id,email,first_name,middle_name,last_name,role_id,staff_number,student_number,status,expires_at,accepted_at,created_at,role:roles(id,name,code)")
    .eq("institution_id", institutionId)
    .order("created_at", { ascending: false });
}

export async function listAssignableRoles(institutionId) {
  return supabase
    .from("roles")
    .select("id,name,code,institution_id,is_active")
    .eq("is_active", true)
    .or(`institution_id.is.null,institution_id.eq.${institutionId}`)
    .not("code", "in", "(owner,student,parent)")
    .order("name");
}

export async function createInvitation(payload) {
  const { data, error } = await supabase.functions.invoke("invite-user", {
    body: {
      institution_id: payload.p_institution_id,
      email: payload.p_email,
      role_id: payload.p_role_id,
      first_name: payload.p_first_name,
      middle_name: payload.p_middle_name,
      last_name: payload.p_last_name,
      redirect_to: `${window.location.origin}/reset-password`,
    },
  });
  if (!error && data?.ok === false) return { data: null, error: new Error(data.error) };
  return { data, error };
}

export async function refreshInvitationRecord(invitation) {
  const { data, error } = await supabase.functions.invoke("invite-user", {
    body: {
      invitation_id: invitation.id,
      institution_id: invitation.institution_id,
      email: invitation.email,
      role_id: invitation.role_id,
      first_name: invitation.first_name,
      middle_name: invitation.middle_name,
      last_name: invitation.last_name,
      redirect_to: `${window.location.origin}/reset-password`,
    },
  });
  if (!error && data?.ok === false) return { data: null, error: new Error(data.error) };
  return { data, error };
}

export function acceptOwnInvitation() {
  return supabase.rpc("accept_own_user_invitation");
}

export function revokeInvitation(id) {
  return supabase.rpc("revoke_user_invitation", { p_invitation_id: id });
}

export function changeUserRole(institutionUserId, roleId) {
  return supabase.rpc("change_institution_user_role", {
    p_institution_user_id: institutionUserId,
    p_role_id: roleId,
  });
}

export function setUserStatus(institutionUserId, status) {
  return supabase.rpc("set_institution_user_status", {
    p_institution_user_id: institutionUserId,
    p_status: status,
  });
}
