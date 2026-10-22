import { Link } from "react-router-dom";
import { GraduationCap, Users, BookOpen, ClipboardCheck, CalendarDays, UserRoundCog, Globe2, Settings, ListChecks, LockKeyhole } from "lucide-react";
import { useWorkflow } from "../../contexts/WorkflowContext";

const modules = [
 ["Institution Settings","Maintain designated institutional resources and settings.","/admin/settings",Settings],
 ["User Management","Request staff invitations and role assignments for independent approval.","/admin/users",UserRoundCog],
 ["Website Management","Manage the school's public website content.","/admin/website",Globe2],
];

export default function AdminDashboard() {
  const { isComplete, completedCount, totalSteps, loading } = useWorkflow();
  const percent = Math.round((completedCount / totalSteps) * 100);
  return <section>
    <div className="page-heading"><span className="eyebrow">Day-to-day management</span><h1>University Administration</h1><p>Manage user accounts, designated resources and the public website. Academic and financial duties require separately approved roles.</p></div>
    <Link to="/admin/setup" className="setup-banner"><div className="action-icon"><ListChecks size={22}/></div><div><strong>Implementation readiness: {loading ? "…" : `${percent}%`}</strong><span>{completedCount} of {totalSteps} setup stages complete · View setup workflow →</span></div></Link>
    <div className="action-grid">
      {modules.map(([title,text,to,Icon,requires]) => {
        const disabled = requires && (loading || !isComplete(requires));
        if (disabled) return <div className="action-card action-card-disabled" key={to}><div className="action-icon"><Icon size={22}/></div><div><h3>{title}</h3><p>{text}</p><span><LockKeyhole size={14}/> Complete prerequisite setup</span></div></div>;
        return <Link className="action-card" to={to} key={to}><div className="action-icon"><Icon size={22}/></div><div><h3>{title}</h3><p>{text}</p><span>Open module →</span></div></Link>;
      })}
    </div>
  </section>;
}
