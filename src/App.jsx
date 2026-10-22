import Operations152 from './pages/dashboard/Operations152';
import AcademicSupport138 from './pages/dashboard/AcademicSupport138';
import CommitteeReview130 from './pages/dashboard/CommitteeReview130';
import DeputyAuthority129 from './pages/dashboard/DeputyAuthority129';
import SchoolDashboard127 from './pages/dashboard/SchoolDashboard127';
import AuditorWorkspace116 from "./pages/dashboard/AuditorWorkspace116";
import TechnicalSupport151 from "./pages/dashboard/TechnicalSupport151";
import PlatformWorkspace116 from "./pages/dashboard/PlatformWorkspace116";
import { Navigate, Route, Routes } from "react-router-dom";
import Login from "./pages/auth/Login";
import StudentLogin from "./pages/auth/StudentLogin";
import ForgotPassword from "./pages/auth/ForgotPassword";
import ResetPassword from "./pages/auth/ResetPassword";
import AuthCallback from "./pages/auth/AuthCallback";
import ProtectedRoute from "./routes/ProtectedRoute";
import RoleRoute from "./routes/RoleRoute";
import DashboardLayout from "./layouts/DashboardLayout";
import PortalRedirect from "./pages/dashboard/PortalRedirect";
import OwnerDashboard from "./pages/dashboard/OwnerDashboard";
import AdminDashboard from "./pages/dashboard/AdminDashboard";
import LecturerDashboard from "./pages/dashboard/LecturerDashboard";
import StudentDashboard from "./pages/dashboard/StudentDashboard";
import ParentDashboard from "./pages/dashboard/ParentDashboard";
import SetupReadiness from "./pages/dashboard/SetupReadiness";
import AdministratorManagement from "./pages/dashboard/AdministratorManagement";
import UserManagement from "./pages/dashboard/UserManagement116";
import AcademicsManagement from "./pages/dashboard/AcademicsManagement";
import AdmissionsManagement from "./pages/dashboard/AdmissionsManagement";
import ApplicantPortal from "./pages/admissions/ApplicantPortal";
import PublicWebsite from "./pages/public/PublicWebsite";
import WebsiteManagement from "./pages/dashboard/WebsiteManagement";
import InstitutionSettings from "./pages/dashboard/InstitutionSettings";
import StudentSearch from "./pages/dashboard/StudentSearch";
import StudentManagement from "./pages/dashboard/StudentManagement";
import ResultsManagement from "./pages/dashboard/ResultsManagement";
import AcademicIntelligence from "./pages/dashboard/AcademicIntelligence";
import FinanceManagement from "./pages/dashboard/FinanceManagement";
import FinanceReports107 from "./pages/dashboard/FinanceReports107";
import AttendanceManagement from "./pages/dashboard/AttendanceManagement";
import AcademicDocuments115 from "./pages/dashboard/AcademicDocuments115";
import AcademicReports097 from "./pages/dashboard/AcademicReports097";
import LecturerReports115 from "./pages/dashboard/LecturerReports115";
import Workspace101 from "./pages/dashboard/Workspace101";

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route path="/student-login" element={<StudentLogin />} />
      <Route path="/register" element={<Navigate to="/login" replace />} />
      <Route path="/forgot-password" element={<ForgotPassword />} />
      <Route path="/reset-password" element={<ResetPassword />} />
      <Route path="/auth/callback" element={<AuthCallback />} />
      <Route path="/apply" element={<ApplicantPortal />} />
      <Route path="/programmes" element={<PublicWebsite />} />
      <Route path="/admissions" element={<PublicWebsite />} />
      <Route path="/about" element={<PublicWebsite />} />
      <Route path="/research" element={<PublicWebsite />} />
      <Route path="/student-life" element={<PublicWebsite />} />
      <Route path="/projects" element={<PublicWebsite />} />
      <Route path="/alumni" element={<PublicWebsite />} />

      <Route element={<ProtectedRoute />}>
        <Route element={<DashboardLayout />}>
          <Route path="/platform" element={<PlatformWorkspace116 />} />
          <Route path="/dashboard" element={<PortalRedirect />} />
          <Route element={<RoleRoute roles={["owner","registrar","exam_officer","academic_panel"]} />}><Route path="/academic-review" element={<CommitteeReview130 />} /></Route>

          <Route element={<RoleRoute roles={["deputy_access_authority"]} />}><Route path="/access-authority" element={<DeputyAuthority129 />} /></Route>
          <Route element={<RoleRoute roles={["owner"]} />}>
            <Route path="/owner" element={<OwnerDashboard />} />
            <Route path="/owner/home" element={<Navigate to="/owner" replace />} />
            <Route path="/owner/dashboard" element={<Navigate to="/owner" replace />} />
            <Route path="/owner/website" element={<WebsiteManagement />} />
            <Route path="/owner/setup" element={<SetupReadiness />} />
            <Route path="/owner/payroll" element={<Operations152 domain="payroll" />} />
            <Route path="/owner/users" element={<AdministratorManagement />} />
            <Route path="/owner/deputies" element={<DeputyAuthority129 />} />
            <Route path="/owner/roles" element={<UserManagement />} />
            <Route path="/owner/support" element={<TechnicalSupport151 />} />
            <Route path="/owner/audit" element={<AuditorWorkspace116 />} />
            <Route path="/owner/finance-reports" element={<FinanceReports107 />} />
            <Route path="/owner/hr" element={<Operations152 domain="hr" />} />
            <Route path="/owner/procurement" element={<Operations152 domain="procurement" />} />
            <Route path="/owner/library" element={<Operations152 domain="library" />} />
            <Route path="/owner/accommodation" element={<Operations152 domain="hostel" />} />
            <Route path="/owner/settings" element={<InstitutionSettings />} />
          </Route>

          <Route element={<RoleRoute roles={["admin"]} />}>
            <Route path="/admin" element={<AdminDashboard />} />
            <Route path="/admin/setup" element={<SetupReadiness />} />
            <Route path="/admin/users" element={<UserManagement />} />
            <Route path="/admin/website" element={<WebsiteManagement />} />
            <Route path="/admin/settings" element={<InstitutionSettings />} />
            <Route path="/admin/payroll-workspace" element={<Operations152 domain="payroll" />} />
            <Route path="/admin/hr" element={<Operations152 domain="hr" />} />
            <Route path="/admin/procurement" element={<Operations152 domain="procurement" />} />
            <Route path="/admin/library" element={<Operations152 domain="library" />} />
            <Route path="/admin/accommodation" element={<Operations152 domain="hostel" />} />
            <Route path="/admin/communications" element={<WebsiteManagement />} />
            <Route path="/admin/system-settings" element={<InstitutionSettings />} />

          </Route>

          <Route element={<RoleRoute roles={["owner","registrar","exam_officer"]} />}>
            <Route path="/admin/admissions" element={<AdmissionsManagement />} />
            <Route path="/admin/student-search" element={<StudentSearch />} />
            <Route path="/admin/students" element={<StudentManagement />} />
            <Route path="/admin/academics" element={<AcademicsManagement />} />
            <Route path="/admin/results" element={<ResultsManagement />} />
            <Route path="/admin/academic-intelligence" element={<AcademicIntelligence />} />
            <Route path="/admin/attendance" element={<AttendanceManagement />} />
            <Route path="/admin/academic-workspace" element={<Workspace101 type="academic" />} />
            <Route path="/admin/academic-documents" element={<AcademicDocuments115 />} />
            <Route path="/admin/reports" element={<AcademicReports097 />} />
          </Route>
          <Route element={<RoleRoute roles={["owner","finance_officer"]} />}>
            <Route path="/admin/finance" element={<Navigate to="/admin/finance/operations" replace />} />
            <Route path="/admin/finance/operations" element={<FinanceManagement workspace="operations" />} />
            <Route path="/admin/finance/reports" element={<FinanceReports107 />} />
          </Route>
          <Route element={<RoleRoute roles={["registrar"]} />}>
            <Route path="/registrar/academic-documents" element={<AcademicDocuments115 />} />
            <Route path="/registrar/reports" element={<AcademicReports097 />} />
            <Route path="/registrar/student-search" element={<StudentSearch />} />
            <Route path="/registrar" element={<SchoolDashboard127 role="registrar" />} />
            <Route path="/registrar/home" element={<Navigate to="/registrar" replace />} />
            <Route path="/registrar/dashboard" element={<Navigate to="/registrar" replace />} />
            <Route path="/registrar/users" element={<UserManagement />} />
            <Route path="/registrar/website" element={<WebsiteManagement />} />
            <Route path="/registrar/hr" element={<Operations152 domain="hr" />} />
            <Route path="/registrar/procurement" element={<Operations152 domain="procurement" />} />
            <Route path="/registrar/library" element={<Operations152 domain="library" />} />
            <Route path="/registrar/accommodation" element={<Operations152 domain="hostel" />} />
            <Route path="/registrar/settings" element={<InstitutionSettings />} />
            <Route path="/registrar/setup" element={<SetupReadiness />} />
          </Route>

          <Route element={<RoleRoute roles={["admissions_officer"]} />}>
            <Route path="/admissions" element={<AdmissionsManagement />} />
          </Route>

          <Route element={<RoleRoute roles={["auditor"]} />}>
            <Route path="/audit" element={<AuditorWorkspace116 />} />
            <Route path="/audit/hr" element={<Operations152 domain="hr" />} />
<Route path="/audit/procurement" element={<Operations152 domain="procurement" />} />
<Route path="/audit/hostel" element={<Operations152 domain="hostel" />} />
<Route path="/audit/payroll" element={<Operations152 domain="payroll" />} />
<Route path="/audit/library" element={<Operations152 domain="library" />} />
            <Route path="/audit/reports" element={<FinanceReports107 />} />
          </Route>

          <Route element={<RoleRoute roles={["finance_officer"]} />}>
            <Route path="/finance" element={<Navigate to="/finance/operations" replace />} />
            <Route path="/finance/operations" element={<FinanceManagement workspace="operations" />} />
            <Route path="/finance/payroll" element={<Operations152 domain="payroll" />} />
            <Route path="/finance/procurement" element={<Operations152 domain="procurement" />} />
            <Route path="/finance/accommodation" element={<Operations152 domain="hostel" />} />
            <Route path="/finance/reports" element={<FinanceReports107 />} />
          </Route>

          <Route element={<RoleRoute roles={["owner","admin","registrar","hr_officer","payroll_officer","procurement_officer","accommodation_officer","librarian","lecturer","staff","finance_officer"]} />}>
            <Route path="/employee-services" element={<Operations152 domain="self" />} />
          </Route>
          <Route element={<RoleRoute roles={["procurement_officer"]} />}>
            <Route path="/procurement" element={<Operations152 domain="procurement" />} />
          </Route>
          <Route element={<RoleRoute roles={["hr_officer"]} />}>
            <Route path="/hr" element={<Operations152 domain="hr" />} />
          </Route>

          <Route element={<RoleRoute roles={["payroll_officer"]} />}>
            <Route path="/payroll" element={<Operations152 domain="payroll" />} />
          </Route>

          <Route element={<RoleRoute roles={["exam_officer"]} />}>
            <Route path="/exams" element={<ResultsManagement />} />
          </Route>

          <Route element={<RoleRoute roles={["librarian"]} />}>
            <Route path="/library" element={<Operations152 domain="library" />} />
          </Route>

          <Route element={<RoleRoute roles={["accommodation_officer"]} />}>
            <Route path="/accommodation" element={<Operations152 domain="hostel" />} />
          </Route>

          <Route element={<RoleRoute roles={["communications_officer"]} />}>
            <Route path="/communications" element={<WebsiteManagement />} />
          </Route>

          <Route element={<RoleRoute roles={["lecturer"]} />}>
            <Route path="/lecturer/employee-services" element={<Operations152 domain="self" />} />
            <Route path="/lecturer/support" element={<AcademicSupport138 lecturer />} />
            <Route path="/lecturer/reports" element={<LecturerReports115 />} />
            <Route path="/lecturer/*" element={<LecturerDashboard />} />
          </Route>

          <Route element={<RoleRoute roles={["student"]} />}>
            <Route path="/student/support" element={<AcademicSupport138 />} />
            <Route path="/student/*" element={<StudentDashboard />} />
          </Route>

          <Route element={<RoleRoute roles={["staff"]} />}>
            <Route path="/staff" element={<Operations152 domain="self" />} />
          </Route>

          <Route element={<RoleRoute roles={["parent"]} />}>
            <Route path="/parent" element={<ParentDashboard />} />
          </Route>
        </Route>
      </Route>

      <Route path="/" element={<PublicWebsite />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}