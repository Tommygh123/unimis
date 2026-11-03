import {schoolModules127,ownerFinance127} from '../../lib/schoolModules127';
import {useEffect,useMemo,useState} from "react";
import {NavLink,useLocation} from "react-router-dom";
import {
 LayoutDashboard,GraduationCap,Users,BookOpen,ClipboardCheck,WalletCards,CalendarDays,Library,
 Building2,UserRoundCog,Banknote,Bell,Settings,X,HeartHandshake,ShieldCheck,ScrollText,Globe2,
 ListChecks,LockKeyhole,ChevronDown,ChevronRight,BrainCircuit,Landmark,FileText,BarChart3,
 UserSearch,School,Boxes,MessagesSquare,ReceiptText,Scale
} from "lucide-react";
import {useUserContext} from "../../contexts/UserContext";
import {useWorkflow} from "../../contexts/WorkflowContext";

import AccountsWorkspaceMenu from "./AccountsWorkspaceMenu";

const schoolGroups127=role=>[
 {key:role+'-home',label:'Dashboard',items:[{label:'Dashboard',path:'/'+role,icon:LayoutDashboard,exact:true}]},
 {key:role+'-academics',label:'Academic Operations & Reports',items:schoolModules127(role).slice(0,['registrar','owner'].includes(role)?8:10).map(([label,pathText,path])=>({label,path,icon:BookOpen}))},
 {key:role+'-school',label:'School Administration',items:schoolModules127(role).slice(['registrar','owner'].includes(role)?8:10).map(([label,text,path])=>({label,path,icon:Building2}))},
 ...(role==='owner'?[{key:'owner-finance',label:'Accounts & Finance',items:ownerFinance127.filter(([,,path])=>path!=='/owner/deputies').slice(0,3).map(([label,text,path])=>({label,path,icon:WalletCards}))},{key:'owner-governance',label:'Access Approvals & Audit',items:[{label:'Deputy Access Authority',path:'/owner/deputies',icon:ShieldCheck},{label:'Access Approvals',path:'/owner/roles',icon:ShieldCheck},{label:'Technical Support Authorisations',path:'/owner/support',icon:ShieldCheck},{label:'Audit Logs',path:'/owner/audit',icon:ScrollText}]}]:[])
];
const ownerGroups=schoolGroups127('owner'),registrarGroups127=schoolGroups127('registrar');

const adminGroups=[
 {key:"admin",label:"School Administration",items:[{label:"Overview",path:"/admin",icon:LayoutDashboard,exact:true},{label:"User Management & Access Requests",path:"/admin/users",icon:UserRoundCog},{label:"Website Management",path:"/admin/website",icon:Globe2},{label:"Institution Settings",path:"/admin/settings",icon:Settings}]}
];
const financeGroups=[{key:"finance",label:"Accounts & Finance",tone:"finance",items:[{label:"Accounts Operations",heading:"OPERATIONS",path:"/finance/operations",icon:WalletCards},{label:"Accounts Reports & Analytics",heading:"REPORTS & ANALYTICS",path:"/finance/reports",icon:BarChart3},{label:"Payroll & Payslips",path:"/finance/payroll",icon:Banknote},{label:"Procurement & Supply",path:"/finance/procurement",icon:Boxes},{label:"Hostel Billing & Allocation",path:"/finance/accommodation",icon:Building2}]}];

const portalItems={
 academic_panel:[["Committees & Results Approvals","/academic-review",ClipboardCheck,true]],
 deputy_access_authority:[["Access Approvals & Reactivation","/access-authority",ShieldCheck,true]],
 auditor:[["Audit & Control Centre","/audit",ShieldCheck,true],["Accounts Reports & Analytics","/audit/reports",BarChart3],["HR Evidence","/audit/hr",Users],["Procurement Evidence","/audit/procurement",Boxes],["Hostel Evidence","/audit/hostel",Building2],["Payroll Evidence","/audit/payroll",Banknote],["Library Evidence","/audit/library",Library]],
 platform_superadmin:[["Technical Dashboard","/platform",LayoutDashboard,true],["Login & Operations Support","/platform?workspace=Support",UserRoundCog],["Access Security & Escalation","/platform?workspace=Security",ShieldCheck],["Updates, Backups & Integrations","/platform?workspace=Maintenance",Settings],["School Module Catalogue","/platform?workspace=Module+Catalogue",BookOpen]],
 registrar:[["Admissions","/admin/admissions",GraduationCap],["Academic Operations","/admin/academic-workspace",BookOpen],["Student Management","/registrar",BookOpen],["Student Search & Lifecycle","/registrar/student-search",Users],["Academic Documents","/registrar/academic-documents",FileText],["Academic Reports","/registrar/reports",BarChart3]],admissions_officer:[["Admissions","/admissions",GraduationCap]],
 finance_officer:[["Accounts Operations","/finance/operations",WalletCards],["Accounts Reports & Analytics","/finance/reports",BarChart3]],hr_officer:[["Human Resources","/hr",UserRoundCog],["My Employee Services","/employee-services",CalendarDays]],procurement_officer:[["Procurement & Supply","/procurement",Boxes],["My Employee Services","/employee-services",CalendarDays]],
 payroll_officer:[["Payroll","/payroll",Banknote]],exam_officer:[["Results & Examinations","/exams",ClipboardCheck],["Committees & Results Approvals","/academic-review",ShieldCheck]],
 librarian:[["Library","/library",Library]],accommodation_officer:[["Accommodation","/accommodation",Building2]],
 communications_officer:[["Communications","/communications",Bell]],
 lecturer:[["Dashboard","/lecturer",LayoutDashboard,true],["My Courses","/lecturer/courses",BookOpen],["My Timetable","/lecturer/timetable",CalendarDays],["Class List","/lecturer/classes",Users],["Attendance","/lecturer/attendance",ClipboardCheck],["Results","/lecturer/results",GraduationCap],["Reports & Teaching History","/lecturer/reports",BarChart3],["Performance & Academic Support","/lecturer/support",BarChart3],["My Employee Services","/lecturer/employee-services",CalendarDays]],
 student:[["Dashboard","/student",LayoutDashboard,true],["Course Registration","/student/registration",BookOpen],["Academic Results","/student/results",ClipboardCheck],["Performance & Academic Support","/student/support",BarChart3],["Academic Record","/student/record",GraduationCap],["Progression","/student/progression",GraduationCap],["Fees & Payments","/student/fees",WalletCards],["Attendance","/student/attendance",CalendarDays],["Profile","/student/profile",Users]],
 staff:[["Staff Portal","/staff",Users]],parent:[["My Ward","/parent",HeartHandshake]]
};
function platformSelected151(isActive,path,search){if(!isActive||!path.startsWith('/platform'))return isActive;return (new URLSearchParams(search).get('workspace')||'Overview')===(new URLSearchParams(path.split('?')[1]||'').get('workspace')||'Overview')}
function active(path,item){const base=item.path.split("?")[0];return item.exact?path===base:path===base||path.startsWith(base+"/")}
export default function Sidebar({open,onClose}){
 const {currentRole}=useUserContext(),{isComplete,loading}=useWorkflow(),location=useLocation(),roleCode=currentRole?.code;
 const groups=useMemo(()=>roleCode==="owner"?ownerGroups:roleCode==="registrar"?registrarGroups127:roleCode==="admin"?adminGroups:roleCode==="finance_officer"?financeGroups:null,[roleCode]);
 const activeKey=useMemo(()=>groups?.find(g=>g.items.some(i=>active(location.pathname,i)))?.key||groups?.[0]?.key,[groups,location.pathname]);
 const [openGroups,setOpenGroups]=useState({});
 useEffect(()=>{if(activeKey)setOpenGroups(c=>({...c,[activeKey]:true}))},[activeKey]);
 const renderItem=({label,path,icon:Icon,requires,exact})=>{const disabled=roleCode==="admin"&&requires&&(loading||!isComplete(requires));return disabled?<div key={label+path} className="nav-link nav-disabled"><Icon size={18}/><span>{label}</span><LockKeyhole size={14}/></div>:<NavLink key={label+path} to={path} end={!!exact} onClick={onClose} className={({isActive})=>`nav-link${platformSelected151(isActive,path,location.search)?" active":""}`}><Icon size={18}/><span>{label}</span></NavLink>};
 return <><button type="button" aria-label="Close navigation" className={open?"sidebar-backdrop show":"sidebar-backdrop"} onClick={onClose}/><aside className={open?"sidebar open":"sidebar"}><div className="sidebar-brand"><div className="brand-badge">U</div><div><strong>UniMIS</strong><small>{currentRole?.name||"Portal"}</small></div><button type="button" className="sidebar-close" onClick={onClose}><X size={20}/></button></div><nav className="sidebar-nav">{groups?groups.map(g=>{const ex=!!openGroups[g.key];if(g.key==="finance")return <div className="sidebar-menu-group tone-finance" key={g.key}><div className="accounts-finance-heading110">Accounts & Finance</div><AccountsWorkspaceMenu base={roleCode==="admin"?"/admin/finance":"/finance"} onClose={onClose}/>{g.items.filter(i=>i.path.includes("procurement")||i.path.includes("accommodation")||i.path.includes("payroll")).map(renderItem)}</div>;if(g.items.length===1){const i=g.items[0],Icon=i.icon;return <NavLink key={g.key} to={i.path} end={!!i.exact} onClick={onClose} className={({isActive})=>`sidebar-workspace-link tone-${g.tone||"default"}${isActive?" active":""}`}><Icon size={19}/><span>{g.label}</span><ChevronRight size={16}/></NavLink>}return <div className={`sidebar-menu-group tone-${g.tone||"default"}${g.key===activeKey?" active-group":""}`} key={g.key}><button type="button" className="sidebar-group-toggle" onClick={()=>setOpenGroups(c=>({[g.key]:!c[g.key]}))}><span>{g.label}</span>{ex?<ChevronDown size={16}/>:<ChevronRight size={16}/>}</button>{ex&&<div className="sidebar-submenu">{g.items.map(i=><div key={i.path}>{i.heading&&<div className="sidebar-subheading108">{i.heading}</div>}{renderItem(i)}</div>)}</div>}</div>}):(portalItems[roleCode]||[["Dashboard","/dashboard",LayoutDashboard]]).map(([label,path,icon,exact])=>renderItem({label,path,icon,exact}))}</nav></aside></>
}