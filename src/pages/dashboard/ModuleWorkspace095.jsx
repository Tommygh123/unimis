import {Link} from "react-router-dom";
import {FileText,BarChart3,Users,GraduationCap,ClipboardCheck,CalendarDays,BookOpen} from "lucide-react";
import "../../styles/module-workspaces-095.css";
const configs={
 documents:{eyebrow:"REGISTRY",title:"Academic Documents",text:"Generate and manage official student academic documents.",cards:[
  ["Result Slips","Semester result slips from officially published results.","/admin/students",ClipboardCheck],
  ["Academic Transcripts","Complete published academic record, GPA/CGPA and award details.","/admin/students",FileText],
  ["Statements of Results","Registry-issued academic statements.","/admin/students",BookOpen],
  ["Document Issue History","Track official documents issued by Registry.","/admin/academic-documents",FileText]]},
 reports:{eyebrow:"MANAGEMENT REPORTING",title:"Academic Reports",text:"Institution-wide academic reporting. Finance reports remain in Accounts / Finance.",cards:[
  ["Student Population","Population by academic year, faculty, department, programme and level.","/admin/reports",Users],
  ["Registration Reports","Registration by academic year and semester.","/admin/reports",CalendarDays],
  ["Academic Performance","Pass rates, GPA/CGPA and course performance.","/admin/academic-intelligence",BarChart3],
  ["Progression & Trails","Promoted, repeat, probation, deferred and trail students.","/admin/students",GraduationCap],
  ["Graduation Reports","Eligible, exceptions, graduates and classifications.","/admin/students",GraduationCap],
  ["Attendance Reports","Attendance by period, programme, course and student.","/admin/attendance",ClipboardCheck]]}
};
export default function ModuleWorkspace({type}){const c=configs[type];return <div className="management-page workspace095"><header><span className="section-kicker">{c.eyebrow}</span><h1>{c.title}</h1><p>{c.text}</p></header><div className="workspace-grid095">{c.cards.map(([t,d,to,I])=><Link to={to} key={t} className="workspace-card095"><I size={23}/><div><h3>{t}</h3><p>{d}</p></div></Link>)}</div></div>}
