# Preparing a private GitHub repository

The organizer only prepares files; it does not create or push a repository.

1. Verify the existing app and demo login after folder organization.
2. Make a full private backup using scripts/Backup_Local.ps1.
3. If no repository exists, run `git init` from C:\unimis.
4. Run `powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\Check_Git_Ready.ps1"`.
5. Review `git status --short`. Confirm local secrets, dumps, archives and
   node_modules do not appear as files to add.
6. Stage the intended source files. Review `git diff --cached --stat` and the
   staged changes. Run the Git check again before committing.
7. Create a private GitHub repository and connect its actual remote URL.
   Push only after reviewing the staged contents.

The check is a basic filter, not a full secret/security audit. If secrets were
previously committed, ignoring the file now does not remove Git history;
rotate exposed secrets and review repository history before publishing.

Demo passwords in demo/Credentials.csv are intentional fictional training
credentials. They must never be reused as real-school production passwords.
Private database snapshots and Storage files belong in separate restricted
backup storage. GitHub source code does not back up Docker database volumes.
