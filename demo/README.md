# UniMIS demonstration school

This is the maintained demo package, consolidated from recreation update 156.
Use your Two Phase Demonstration Guide 149 for presentation and training.

## Install only when creating or preparing the demo

From C:\unimis:

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -File "demo\Install.ps1"
```

It prepares a separate school called **UniMIS Demonstration & Training - 148**.
Main-school `kk@gmail.com` and `pp@gmail.com` are separate. It makes a local
database snapshot first; it never resets the database. Current results await
review/publication and the eligible candidate awaits graduation decisions.

Demo Owner: `e2e117.authority@unimis.test`.
Demo Registrar: `e2e117.registrar@unimis.test`.
Demo account password: `UniMIS117!Test`.
All fictional logins: `Credentials.csv`. Blank applicant:
`demo148.live@unimis.test` / `UniMIS148!Demo`.

Once installed, demo records stay in the database. Do not run the installer
every time you start UniMIS. Repeating it retains progress, restores published
demo passwords and selects Semester 1; it is not a clean reset.

## Later stages

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -File "demo\Run_Stages.ps1" -Stage Semester2
```

Other stages: Register, Bill, Attendance, Results -SubmitOnly, NextYear,
RestoreSemester1. Calendar changes do not approve results or promote students.
Use the normal academic workspaces for approval, publication and graduation.

The compact 48-credit curriculum is fictional. The package includes academic,
admissions and finance examples, not full HR/payroll/procurement/hostel data.
Use only on a local demonstration installation. Its current Docker-dependent
installer is not a hosted Supabase provisioning/reset tool. Before online
publication, prepare and validate a separate hosted setup; do not paste this
local seed into a live school project.

For trainee assessment, copy `Training_Assessment_Template.csv` to
`Training_Assessment.csv`. The completed copy is excluded from Git.
