UniMIS stability fix

What was corrected
1. Restored the working role/membership-first login flow.
2. Removed the browser-side role_permissions query that was returning HTTP 403.
3. A permissions failure can no longer make a valid Owner/Admin appear unassigned.
4. PortalRedirect now distinguishes a real loading/database error from a genuinely unassigned account.
5. The existing AdministratorManagement page is now wired to /owner/users instead of the generic placeholder.

Why
The previous RBAC update made the permission lookup part of the critical login path. Your database showed the Owner membership was valid, but /rest/v1/role_permissions returned 403. That prevented the context from completing and caused the misleading Account not assigned screen.

Next
Build Admin User Management (/admin/users): invitation, role assignment, activation/deactivation, resend invite, and status tracking.

Do not add permission-level route enforcement yet. We will reintroduce that later through a dedicated get_my_permissions RPC so it does not depend on a fragile direct RLS join.
