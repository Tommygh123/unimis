UniMIS User Management React module

Wired route: /admin/users
Uses existing migration objects:
- institution_user_directory
- user_invitations
- create_user_invitation
- refresh_user_invitation
- revoke_user_invitation
- set_institution_user_status
- change_institution_user_role

This version creates/tracks invitation records locally. It intentionally does NOT expose a service-role key in React or send Auth invitation email yet. Secure email invitation is the next step.
