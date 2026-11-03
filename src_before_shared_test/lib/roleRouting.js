export const rolePriority = [
  "owner", "auditor", "admin", "registrar", "admissions_officer", "finance_officer",
  "procurement_officer", "hr_officer", "payroll_officer", "exam_officer", "communications_officer",
  "librarian", "accommodation_officer", "lecturer", "staff", "student", "parent",
];

export function portalForRole(code) {
  const portals = {
    academic_panel:"/academic-review",deputy_access_authority:"/access-authority",auditor: "/audit",owner: "/owner", admin: "/admin", registrar: "/registrar",
    admissions_officer: "/admissions", finance_officer: "/finance",
    procurement_officer:"/procurement", hr_officer: "/hr", payroll_officer: "/payroll", exam_officer: "/exams",
    communications_officer: "/communications", librarian: "/library",
    accommodation_officer: "/accommodation", lecturer: "/lecturer",
    staff: "/staff", student: "/student", parent: "/parent",
  };
  return portals[code] || "/dashboard";
}
