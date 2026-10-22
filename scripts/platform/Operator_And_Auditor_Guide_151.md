# UniMIS 151 — Technical Operations and Independent Audit

## Install in the working project
Extract the ZIP into C:\unimis. Run `npx supabase migration up --local`. Refresh the UI. The package includes the Owner/Registrar navigation from 150C. No test data is deleted and no account is automatically made Superadmin.

## Create your separate technical account
Use local Supabase Studio → Authentication → Users → Add user to create a dedicated account with a unique email and strong password. Confirm its email through the appropriate local Auth process. Do not assign a school membership. Do not use kk@gmail.com, pp@gmail.com, or e2e117.authority@unimis.test; those are school accounts. Authentication account creation and platform authorisation are separate steps.

Run these commands from CMD:
```
cd /d C:\unimis && docker cp "C:\unimis\operator151\Grant_Platform_151.sql" supabase_db_unimis:/tmp/Grant_Platform_151.sql && docker exec -it supabase_db_unimis psql -U postgres -d postgres -f /tmp/Grant_Platform_151.sql
```
Enter the separate technical account's email when prompted. The protected script rejects accounts with school memberships. Sign out and sign in with that technical account; it routes to /platform. School users cannot grant platform access through the application. Database administrators retain infrastructure authority and must protect their credentials. For a remote installation use the same reviewed script from its protected database administration process; never put service keys or database passwords in front-end code.

Revocation uses operator151\Revoke_Platform_151.sql through the same protected psql process. It disables the platform designation and revokes pending/approved support scopes. Preserve a separate protected recovery process; do not share a technical login.

## Responsibilities
| Technical Operator | School authority | Auditor |
|---|---|---|
| Software updates, integrations, hosting, incident diagnosis, backup evidence and installation provisioning | Staff appointments, policies, admissions, academic publication, graduation and financial authorisations | Independent evidence testing and reporting |
| Separate protected identity | Own institutional decisions and records | School-scoped, read-only operational access |
| No automatic academic/financial approval role | Approves scoped technical support | Can create immutable audit observations, not change the transactions |

## Dashboard workspaces
Overview: registered installations and actual database reachability/version. This is not a live hosting/Docker/payment-provider/backup health monitor.
Support: request a school, login or operations diagnostic scope and a reason. The school Owner opens Access Approvals & Audit → Technical Support Authorisations, records a note and approves 1–8 hours. The same operator cannot approve their own request. Expired/revoked grants fail on the server even if an old button remains visible. Login diagnostics return email-confirmation/banned-until/last-sign-in indicators, membership state and invitation state for one exact school account. Operations diagnostics return aggregate queue counts. No passwords, recovery links or service secrets are displayed. The Operator cannot reset another person's password or activate their school membership through this dashboard. Use the user's normal Forgot Password process or school authority's authorised reactivation flow.
Security: current platform/school separation and additional-role approval provenance counters. Investigate exceptions; primary-role provenance and all unsuccessful login attempts are not automatically established by these checks. Existing school escalation guards remain intact.
Maintenance: incident, deployment, backup, restore, integration and licence evidence records with references and notes. These are operator attestations, not automated successful backups or subscriptions. Do not enter secrets.
Module Catalogue: school menus, descriptions and route references, plus Lecturer/Student responsibilities. This shows coverage without bypassing school roles or impersonating a user. Full sensitive-record troubleshooting requires the school's separately authorised staff to participate; the support grants here do not expose whole academic or finance portals.

## Resolve a login challenge
1. Confirm email, school, invitation acceptance and active membership.
2. Obtain approved login scope, enter exact email and run diagnostics.
3. If invited, verify local invitation in Mailpit at http://127.0.0.1:54324. Keep `npx supabase functions serve --env-file supabase\.env.local` running when functions are required.
4. User uses Forgot Password; never ask for or set a shared password.
5. School authority reactivates authorised inactive school membership. Sign in again after role changes.
6. Record incident reference and outcome. Failed Auth/Edge requests still need their response and runtime logs; the dashboard cannot prove a network service is healthy.

## Updates: local and remote
Local: preserve database/storage/project backup; test release in a separate copy; extract the approved update; apply its migrations if present; run npm run build; restart changed functions; verify login, academic and receipt paths with school staff. Record release and backup references. Do not reset a school's database to install an update.
Remote: versioned repository → staging verification → backup and school maintenance window → reviewed database migrations/functions → front-end deployment → smoke checks → recorded release/rollback evidence. Hosting configuration is installation-specific. Browser buttons do not run Docker, edit a PC or deploy a server. A rollback involving database changes may require the preserved database and storage, not just old React files.
Provisioning: follow the existing approved school setup/onboarding workflow; create its own Owner/Admin; record installation evidence. This update does not automatically provision hosting, billing subscriptions or a new school.

## Auditor: practical control testing
Sign in as e2e117.auditor@unimis.test / UniMIS117!Test for the demo school. An Owner may also inspect the centre, but the professional independent audit should use a separate Auditor account. Auditor access cannot be combined with operational roles.
1. Open Audit & Control Centre. Select From/To and optional academic year/semester.
2. Run & Save Control Snapshot. The saved run records its actor, scope, timestamp and exact exception counts, with at most 100 evidence references per check.
3. Inspect each check's scope. Semester applies to published-result checks; finance uses payment/invoice/journal dates; access and graduation are current-state controls.
4. View Live Evidence for a sample. It can differ from the snapshot if authorised school staff corrected the record later.
5. Record Observation with severity, reference, supported finding and recommendation. Observations are immutable; use a later observation/run to document follow-up.
6. Open Activity & Access for recorded school/security/access/support events. Limited lists are explicitly labelled; empty logs do not prove no events occurred.
7. Print / Save PDF Report for the selected run/domain and linked observations, or export Excel Control Summary.
8. School management implements authorised corrections. Rerun and compare preserved runs; Auditor does not change marks, invoices or payments.

## Implemented checks and independent evidence
| Check | Automated test | Follow-up |
|---|---|---|
| FIN01 | Posted journal empty/unbalanced | Source document, correct account posting and GL |
| FIN02 | Completed non-waiver student payment lacks receipt | Receipt sequence and payment acknowledgement |
| FIN03 | Completed non-waiver student payment lacks posted source journal | Cash/bank source and ledger linkage |
| FIN04 | Voided payment still completed or reversed payment lacks posted reversal | Original receipt, approval/reason, reversal, report exclusion |
| FIN05 | Stored invoice paid amount differs from lifetime completed payments in invoice currency | Components/adjustments and financial statement reconciliation |
| FIN06 | Verified GHS application fee lacks application-fee income journal | Application reference, payment evidence, income account |
| ACA01 | Published result lacks approval identity/time or publication time | Original assessment, authorised review and publication evidence |
| ACA02 | Published result lacks grade/grade point | Grading scale, marking components and calculation |
| ACA03 | Graduated student lacks approved, dated graduation record | Academic approval and dated finalisation |
| ACA04 | Graduated record retains trail/credit shortfall | Complete record, resit evidence and graduation policy |
| ACC01 | Additional role lacks matching approved independent request | Request, recipient, role, school, reviewer and execution |
| ACC02 | Active technical operator has a school membership | Protected provisioning and separation of responsibilities |

Exceptions are prompts for investigation, not findings of fraud. Demo/historical seeded records may intentionally lack authentic approval provenance. FIN06 currently tests GHS posting only, consistent with the implemented application-fee journal workflow. The controls do not recalculate every GPA, verify WAEC externally, inspect all admissions rules, prove bank settlement, perform restore tests or establish complete historical logging. Zero exceptions is not a comprehensive audit opinion.

## Validation and practical limits
Changed JSX compiled with esbuild. The migration and RPCs were executed in isolated PostgreSQL-compatible PGlite against a minimal schema reflecting the used columns. Tested Lecturer/Operator/Auditor boundaries, independent support approval, scope expiry, cross-school denial, evidence retrieval, check counts, immutable observations and direct table-write denial. Your live Docker database/hosting/Windows browser was not available here; run the supplied local migration and inspect the actual dashboards before a production release.
