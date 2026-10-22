UniMIS RBAC update

Changes:
- Preserves existing Owner/Admin dashboards and workflow gating.
- Uses the existing database permissions already loaded by UserContext.
- Adds src/lib/navigationConfig.js as the central menu/permission map.
- Sidebar now hides menu items the current user lacks permission to view.
- App routes for Owner/Admin management areas now also require the matching permission.
- Adds components/PermissionGuard.jsx for buttons/sections inside pages.
- Strengthens UserContext error handling for profile and permission queries.

Important:
- This is UI/route authorization. Supabase RLS remains the final database security layer.
- The existing 'staff' route is preserved even though the role summary supplied did not show a staff role.
