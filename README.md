# UniMIS

University administration, admissions, teaching, results, progression,
graduation, student finance and supporting operations.

## Project folders

- `src` and `public`: application code and public assets.
- `supabase/migrations`: the repaired system migration history. Keep it intact.
- `supabase/functions`: payment and user-invitation Edge Functions.
- `demo`: one optional demonstration school installer and fictional assets.
- `scripts`: local account setup, backup and Git checks.
- `scripts/platform`: protected local technical-operator provisioning tools.
- `docs`: setup and demonstration instructions.
- `security`: existing technical administration SQL, if present.

## Existing installation

Run `npm run dev`. To run local Edge Functions, use the existing
`npm run functions` script after configuring `supabase/.env.local` privately.
Folder organization does not change any database records or current credentials.

## New PC or empty local database

Follow `docs/SECOND_PC.md`. Application code and migrations rebuild structure;
a database and Storage backup preserve existing users, records and files.
Do not reset an existing database to perform a folder cleanup.

## Optional demonstration school

See `demo/README.md`. Install explicitly after database startup. Demo data is
not automatically inserted by application startup or system migrations.

## Before GitHub

Use a private repository. Run `scripts/Check_Git_Ready.ps1` before committing.
Never commit `.env`, function secrets, database dumps, private uploaded files,
or local backup folders. `.gitignore` does not untrack previously committed files.
The demo contains published fictional training passwords; it is not production
account provisioning. Platform operators remain separate from school approvers.
