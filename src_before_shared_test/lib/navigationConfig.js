import {
  LayoutDashboard, GraduationCap, Users, BookOpen, ClipboardCheck, WalletCards,
  CalendarDays, Library, Building2, UserRoundCog, Banknote, Bell, Settings,
  HeartHandshake, ShieldCheck, ScrollText, Globe2, ListChecks,
} from "lucide-react";
export const ownerItems = [
  { label: "Overview", path: "/owner", icon: LayoutDashboard },
  { label: "Administrators", path: "/owner/users", icon: UserRoundCog, permission: "users.view" },
  { label: "Roles & Permissions", path: "/owner/roles", icon: ShieldCheck, permission: "roles.view" },
  { label: "Audit Logs", path: "/owner/audit", icon: ScrollText, permission: "audit.view" },
  { label: "System Settings", path: "/owner/settings", icon: Settings, permission: "settings.view" },
];
export const adminItems = [
  { label: "Dashboard", path: "/admin", icon: LayoutDashboard },
  { label: "Setup Readiness", path: "/admin/setup", icon: ListChecks, permission: "settings.view" },
  { label: "Institution Settings", path: "/admin/settings", icon: Settings, permission: "settings.view" },
  { label: "Academics", path: "/admin/academics", icon: BookOpen, permission: "academics.view" },
  { label: "Admissions", path: "/admin/admissions", icon: GraduationCap, permission: "admissions.view" },
  { label: "Students", path: "/admin/students", icon: Users, permission: "students.view" },
  { label: "Results", path: "/admin/results", icon: ClipboardCheck, permission: "results.view", requires: "results_ready" },
  { label: "User Management", path: "/admin/users", icon: UserRoundCog, permission: "users.view" },
  { label: "Website Management", path: "/admin/website", icon: Globe2, permission: "website.manage" },
];
export const portalItems = {
  registrar: [
    { label: "Student Records", path: "/registrar", icon: Users, permission: "students.view" },
    { label: "Academic Documents", path: "/registrar/academic-documents", icon: BookOpen, permission: "students.view" },
    { label: "Academic Reports", path: "/registrar/reports", icon: BookOpen, permission: "students.view" },
  ],
  admissions_officer: [
    { label: "Admissions", path: "/admissions", icon: GraduationCap, permission: "admissions.view" },
  ],
  finance_officer: [
    { label: "Accounts Operations", path: "/finance/operations", icon: WalletCards, permission: "finance.view" },
    { label: "Accounts Reports & Analytics", path: "/finance/reports", icon: WalletCards, permission: "finance.view" },
  ],
  hr_officer: [
    { label: "Human Resources", path: "/hr", icon: UserRoundCog, permission: "hr.view" },
  ],
  payroll_officer: [
    { label: "Payroll", path: "/payroll", icon: Banknote, permission: "payroll.view" },
  ],
  exam_officer: [
    { label: "Examinations", path: "/exams", icon: ClipboardCheck, permission: "results.view" },
  ],
  librarian: [
    { label: "Library", path: "/library", icon: Library, permission: "library.view" },
  ],
  accommodation_officer: [
    { label: "Accommodation", path: "/accommodation", icon: Building2, permission: "accommodation.view" },
  ],
  communications_officer: [
    { label: "Communications", path: "/communications", icon: Bell, permission: "communications.view" },
  ],
  lecturer: [
    { label: "Lecturer Portal", path: "/lecturer", icon: BookOpen, permission: "academics.view" },
    { label: "Reports & Teaching History", path: "/lecturer/reports", icon: BookOpen },
    { label: "Performance & Academic Support", path: "/lecturer/support", icon: BookOpen },
  ],
  student: [
    { label: "Student Portal", path: "/student", icon: GraduationCap },
    { label: "Performance & Academic Support", path: "/student/support", icon: GraduationCap },
  ],
  staff: [
    { label: "Staff Portal", path: "/staff", icon: Users },
  ],
  parent: [
    { label: "My Ward", path: "/parent", icon: HeartHandshake, permission: "guardian.view" },
  ],
};
export function navigationForRole(roleCode) {
  if (roleCode === "owner") return ownerItems;
  if (roleCode === "admin") return adminItems;
  return portalItems[roleCode] || [{ label: "Dashboard", path: "/dashboard", icon: LayoutDashboard }];
}
