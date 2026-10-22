import { createContext, useContext, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";
import { useAuth } from "./AuthContext";
import { portalForRole, rolePriority } from "../lib/roleRouting";

const UserContext = createContext(null);

export function UserProvider({ children }) {
  const { user, loading: authLoading } = useAuth();

  const [additionalRoles,setAdditionalRoles]=useState([]);
  const [selectedRole,setSelectedRole]=useState(null);
  const [platformOperator,setPlatformOperator]=useState(false);
  const [profile, setProfile] = useState(null);
  const [memberships, setMemberships] = useState([]);
  const [permissions, setPermissions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    if (authLoading) return;

    if (!user) {
      setAdditionalRoles([]);setSelectedRole(null);setPlatformOperator(false);
      setProfile(null);
      setMemberships([]);
      setPermissions([]);
      setError("");
      setLoading(false);
      return;
    }

    let cancelled = false;

    async function loadUserContext() {
      setLoading(true);
      setError("");

      const [profileResult, membershipResult] = await Promise.all([
        supabase
          .from("profiles")
          .select("*")
          .eq("id", user.id)
          .maybeSingle(),

        supabase.rpc("unimis_my_portal_memberships118"),
      ]);

      if (cancelled) return;

      // Membership is the critical portal-routing lookup.
      if (membershipResult.error) {
        setProfile(profileResult.data || null);
        setMemberships([]);
        setPermissions([]);
        setError(membershipResult.error.message);
        setLoading(false);
        return;
      }

      // A profile read problem should not erase a valid role/membership.
      setProfile(profileResult.data || null);
      setMemberships(membershipResult.data || []);
      const [extraResult,platformResult]=await Promise.all([supabase.rpc("unimis_my_additional_roles116"),supabase.rpc("unimis_is_platform_operator116")]);
      if(cancelled)return;
      const [deputyResult,panelResult]=await Promise.all([supabase.rpc("unimis_my_deputy_roles129"),supabase.rpc("unimis_my_panel_roles130")]);if(cancelled)return;
      setAdditionalRoles([...(extraResult.data||[]),...(deputyResult.data||[]),...(panelResult.data||[])]);setPlatformOperator(platformResult.data===true);

      /*
       * IMPORTANT:
       * The previous RBAC update queried role_permissions directly from the
       * browser. In the current database that request returns HTTP 403 because
       * of the role_permissions RLS/helper-policy chain.
       *
       * The existing UniMIS UI currently routes by role, not by permission,
       * so a failed permission lookup must never block Owner/Admin login.
       *
       * We intentionally leave permissions empty here for now. We will add a
       * dedicated SECURITY DEFINER "get_my_permissions" RPC when we implement
       * permission-level UI controls. That gives us a clean security boundary
       * without destabilising the already-working role portals.
       */
      setPermissions([]);

      if (profileResult.error) {
        console.warn("UniMIS profile lookup warning:", profileResult.error.message);
      }

      setLoading(false);
    }

    loadUserContext();

    return () => {
      cancelled = true;
    };
  }, [user, authLoading]);

  const currentMembership = useMemo(() => {
    const primary = memberships.find((item) => item.is_primary);
    if (primary) return primary;

    return (
      [...memberships].sort((a, b) => {
        const aIndex = rolePriority.indexOf(a.role?.code);
        const bIndex = rolePriority.indexOf(b.role?.code);
        return (aIndex < 0 ? 999 : aIndex) - (bIndex < 0 ? 999 : bIndex);
      })[0] || null
    );
  }, [memberships]);

  const roles = useMemo(
    () => [...memberships.filter(m=>m.institution_id===currentMembership?.institution_id),...additionalRoles.filter(m=>m.institution_id===currentMembership?.institution_id)].filter(item=>item.role?.is_active!==false).map((item) => item.role?.code).filter(Boolean),
    [memberships,additionalRoles,currentMembership]
  );

  const availableRoles=[...new Map([...memberships,...additionalRoles].filter(m=>m.institution_id===currentMembership?.institution_id&&m.role?.is_active!==false).map(m=>[m.role?.code,m.role])).values()].filter(Boolean);
  const activeRole=availableRoles.find(r=>r.code===selectedRole)||currentMembership?.role;
  const value = {
    profile,
    memberships,
    currentMembership,
    currentRole: activeRole || (platformOperator?{code:"platform_superadmin",name:"Platform Superadmin / Technical Operator"}:null),
    availableRoles,selectRole:code=>{if(availableRoles.some(r=>r.code===code))setSelectedRole(code)},platformOperator,
    institutionId: currentMembership?.institution_id || null,
    permissions,
    roles,
    loading,
    error,
    hasRole: (role) => roles.includes(role),
    hasPermission: (permission) => permissions.includes(permission),
    defaultPortal: platformOperator&&!currentMembership?"/platform":portalForRole(activeRole?.code),
  };

  return <UserContext.Provider value={value}>{children}</UserContext.Provider>;
}

export const useUserContext = () => useContext(UserContext);
