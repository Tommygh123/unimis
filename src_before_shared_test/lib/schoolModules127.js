export const academicModules127=[
 ["Committees & Results Approvals","Scoped panels, meetings, staged review and authorised publication.","/academic-review"],
 ['Admissions','Applications, eligibility, offers and enrolment.','/admin/admissions'],
 ['Students','Enrolment, registration, progression and graduation.','/admin/students'],
 ['Student Search','Find students by programme, level and academic period.','/admin/student-search'],
 ['Academics','Years, semesters, faculties, departments, programmes and courses.','/admin/academics'],
 ['Results & Examinations','Enter, review and publish results.','/admin/results'],
 ['Academic Intelligence','Performance, trails and progression analysis.','/admin/academic-intelligence'],
 ['Academic Documents','Transcripts, final GPA, classification and result slips.','/admin/academic-documents'],
 ['Academic Reports','Reports by year, semester, faculty and department.','/admin/reports']
];
export function schoolModules127(role){const base='/'+role;const modules=[
 ...academicModules127,
 ['User Management','Users and access requests; role changes require independent approval.',base+'/users'],
 ['Website Management','School identity, published programmes, announcements and stories.',base+'/website'],
 ['System Settings','Numbering, registration, grading, progression and degree classification.',base+'/settings'],
 ['Implementation Readiness','Check the school setup stages.',base+'/setup'],
 ['Human Resources','Recruitment, employee records, leave, attendance and performance reviews.',base+'/hr'],
 ['Procurement','Suppliers, requisitions, purchase orders, goods receiving and invoice matching.',base+'/procurement'],
 ['Library','Catalogue, copies, membership, loans and returns.',base+'/library'],
 ['Accommodation','Facilities, tariffs, applications, allocations and student billing.',base+'/accommodation'],
 ['Communications','Manage school announcements through Website Management.',base+'/website']
 ];
 if(!['registrar','owner'].includes(role))return modules;
 const byTitle=Object.fromEntries(modules.map(item=>[item[0],item]));
 const academicOrder=['Academics','Admissions','Students','Results & Examinations','Student Search','Academic Intelligence','Academic Documents','Academic Reports'];
 const academic=academicOrder.map(title=>{const item=[...byTitle[title]];if(title==='Students')item[0]='Student Management';if(title==='Results & Examinations')item[0]='Examinations & Results';return item});
 return [...academic,...modules.filter(([title])=>!academicOrder.includes(title)&&title!=='Committees & Results Approvals')];
}
export const ownerFinance127=[['Deputy Access Authority','Appoint, revoke and audit backup approval authority.','/owner/deputies'],['Accounts Operations','Billing, payments, receipts, expenses, journals and reconciliation.','/admin/finance/operations'],['Accounts Reports & Analytics','Collections, debtors, application income and financial statements.','/owner/finance-reports'],['Payroll','Pay profiles, calculations, independent approval, payslips and payment journals.','/owner/payroll'],['Access Approvals & Audit','Approve role requests and review school activity.','/owner/roles']];
