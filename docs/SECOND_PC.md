# Moving UniMIS to another PC

There are two different goals:

1. **Fresh development/demo installation**: obtain the clean repository, install
   Node and Docker, run `npm ci`, configure local public keys, start local
   Supabase and explicitly install the optional demo if required.
2. **Exact continuation**: also restore a matching full database backup and
   Storage files. This preserves users, existing demo progress and saved records.

Keep Node, Supabase CLI and database image versions with the backup. The
package lock controls npm dependencies; Docker volumes are not stored by Git.
Local keys/secrets must be configured on each machine. Never send them to chat.

Keep one authoritative database if both PCs must see the same records. Two
independent local stacks do not synchronize automatically. A hosted backend
can provide shared records when deliberately configured.

The folder cleanup does not change or squash migrations, restore a database,
reset demo progress, create accounts or deploy anything. A successful fresh
migration replay was previously checked in an isolated PostgreSQL-compatible
harness; it is not a substitute for a full restore test on another PC.

Use `scripts/Backup_Local.ps1` for a private transfer backup while no users
are editing data or uploading files. It saves project files, a custom database
dump, roles, Storage files and version metadata outside the project. It is not
an encrypted archive; keep it private. Test a restore in a separate environment
before relying on it. Do not import roles blindly into hosted Supabase.

Current initial main-school recovery accounts can be provisioned through
`scripts/Setup_Local_Accounts.ps1` on localhost with Docker operator access.
It prompts for passwords and refuses conflicting memberships. It is an
explicit local technical process, not a self-service escalation mechanism.
