UniMIS Admissions Phase 2 Frontend Update

Updated:
- services/admissions.js
- pages/dashboard/AdmissionsManagement.jsx

Adds:
- Admission cycle level: undergraduate/postgraduate/both
- Applicant scope: local/international/both
- Max programme choices
- Payment-required and draft-before-payment settings
- Fee Rules UI backed by admission_fee_rules
- Document Requirements UI backed by admission_document_requirements
- Existing Paystack/offline payment functions preserved
- Existing submit_admission_application boolean RPC preserved

Important:
The separate public Applicant Portal is NOT added in this package yet.
This package first upgrades the internal Admissions Management configuration,
which should be tested before opening applicant self-service RLS/routes.

Replace your existing src with this updated src or copy the changed files.
Then run:
  npm run build
