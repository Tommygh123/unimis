import {NavLink} from "react-router-dom";
import {BookOpen,CalendarDays,ClipboardCheck,BrainCircuit,FileText,BarChart3,Banknote,Users,ReceiptText,Landmark} from "lucide-react";
import "../../styles/workspace-101.css";
const academic=[
 ["Academics","Curriculum, course offerings, lecturer allocation and academic operations.","/admin/academics",BookOpen],
 ["Attendance","Teaching sessions and student attendance.","/admin/attendance",CalendarDays],
 ["Results & Examinations","Marks, approvals, exams committee review and publication.","/admin/results",ClipboardCheck],
 ["Academic Intelligence","Performance analytics and academic decision support.","/admin/academic-intelligence",BrainCircuit],
 ["Academic Documents","Result slips, transcripts and academic documents.","/admin/academic-documents",FileText],
 ["Academic Reports","Population, registration, performance, progression, trails and graduation reports.","/admin/reports",BarChart3]
];
const payroll=[
 ["Payroll Setup","Staff payroll profiles, earnings, deductions and statutory settings.","/admin/hr?section=payroll",Users],
 ["Payroll Processing","Prepare and process payroll periods.","/admin/hr?section=payroll-processing",Banknote],
 ["Payroll Payments","Payment schedules, bank/MoMo/cash records and payslips.","/admin/hr?section=payroll-payments",ReceiptText],
 ["Payroll Reports","Payroll register, deductions, payment and management reports.","/admin/hr?section=payroll-reports",BarChart3]
];
export default function Workspace101({type}){
 const isAcademic=type==="academic", items=isAcademic?academic:payroll;
 return <div className="workspace101"><header className={`workspace101-hero ${isAcademic?"academic":"payroll"}`}><div><small>UNIMIS WORKSPACE</small><h1>{isAcademic?"Academic Operations":"Payroll"}</h1><p>{isAcademic?"One academic workspace for teaching operations, examinations, documents and reports.":"One payroll workspace for setup, processing, payments, payslips and reports."}</p></div>{isAcademic?<BookOpen size={38}/>:<Banknote size={38}/>}</header><div className="workspace101-sections"><div className="workspace101-heading"><h2>{isAcademic?"Operations, Documents & Reporting":"Payroll Operations & Reporting"}</h2><p>Choose an area below. Detailed actions remain inside the workspace instead of overloading the main sidebar.</p></div><div className="workspace101-grid">{items.map(([name,desc,path,Icon])=><NavLink className="workspace101-card" to={path} key={name}><div className="workspace101-icon"><Icon size={21}/></div><div><h3>{name}</h3><p>{desc}</p></div><span>Open →</span></NavLink>)}</div></div></div>
}