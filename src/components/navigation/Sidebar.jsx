import {schoolModules127,ownerFinance127} from '../../lib/schoolModules127';
import {useEffect,useMemo,useState} from "react";
import {NavLink,useLocation, useNavigate} from 'react-router-dom';
import {
 LayoutDashboard,GraduationCap,Users,BookOpen,ClipboardCheck,WalletCards,CalendarDays,Library,
 Building2,UserRoundCog,Banknote,Bell,Settings,X,HeartHandshake,ShieldCheck,ScrollText,Globe2,
 ListChecks,LockKeyhole,ChevronDown,ChevronRight,BrainCircuit,Landmark,FileText,BarChart3,
 UserSearch,School,Boxes,MessagesSquare,ReceiptText,Scale
} from "lucide-react";
import {useUserContext} from "../../contexts/UserContext";
import {useWorkflow} from "../../contexts/WorkflowContext";
import {supabase} from "../../lib/supabase";

import AccountsWorkspaceMenu from "./AccountsWorkspaceMenu";

const schoolGroups127=role=>[
 {key:role+'-home',label:'Dashboard',items:[{label:'Dashboard',path:'/'+role,icon:LayoutDashboard,exact:true}]},
 {key:role+'-academics',label:'Academic Operations & Reports',items:schoolModules127(role).slice(0,['registrar','owner'].includes(role)?8:10).map(([label,pathText,path])=>({label,path,icon:BookOpen}))},
 {key:role+'-school',label:'School Administration',items:schoolModules127(role).slice(['registrar','owner'].includes(role)?8:10).filter(([label,,path])=>!(role==='owner'&&(String(label).toLowerCase().includes('human resources')||String(path).includes('/owner/hr')||String(label).toLowerCase()==='payroll'||String(path).includes('/owner/payroll')))).map(([label,text,path])=>({label,path,icon:Building2}))},
 ...(role==='owner'?[{key:'owner-finance',label:'Accounts & Finance',items:ownerFinance127.filter(([label,,path])=>path!=='/owner/deputies'&&!String(label).toLowerCase().includes('payroll')&&!String(path).includes('/owner/payroll')).slice(0,3).map(([label,text,path])=>({label,path,icon:WalletCards}))},{key:'owner-governance',label:'Access Approvals & Audit',items:[{label:'Deputy Access Authority',path:'/owner/deputies',icon:ShieldCheck},{label:'Access Approvals',path:'/owner/roles',icon:ShieldCheck},{label:'Technical Support Authorisations',path:'/owner/support',icon:ShieldCheck},{label:'Audit Logs',path:'/owner/audit',icon:ScrollText}]}]:[])
];
const ownerGroups=schoolGroups127('owner'),registrarGroups127=schoolGroups127('registrar');

const adminGroups=[
 {key:"admin",label:"School Administration",items:[{label:"Overview",path:"/admin",icon:LayoutDashboard,exact:true},{label:"User Management & Access Requests",path:"/admin/users",icon:UserRoundCog},{label:"Website Management",path:"/admin/website",icon:Globe2},{label:"Institution Settings",path:"/admin/settings",icon:Settings}]}
];
const financeGroups=[{key:"finance",label:"Accounts & Finance",tone:"finance",items:[{label:"Accounts Operations",heading:"OPERATIONS",path:"/finance/operations",icon:WalletCards},{label:"Accounts Reports & Analytics",heading:"REPORTS & ANALYTICS",path:"/finance/reports",icon:BarChart3},{label:"Procurement & Supply",path:"/finance/procurement",icon:Boxes},{label:"Hostel Billing & Allocation",path:"/finance/accommodation",icon:Building2}]}];



const hrItems168=(base)=>[
 {label:"My Employee Services",path:"/employee-services",icon:CalendarDays},
 {label:"HR Dashboard",path:`${base}?workspace=Dashboard`,icon:LayoutDashboard},
 {label:"Recruitment",path:`${base}?workspace=Recruitment`,icon:UserRoundCog},
 {label:"Employees",path:`${base}?workspace=Employees`,icon:Users},
 {label:"Attendance",path:`${base}?workspace=Attendance`,icon:CalendarDays},
 {label:"Staff Leave",path:`${base}?workspace=Staff+Leave`,icon:CalendarDays},
 {label:"Staff Performance",path:`${base}?workspace=Staff+Performance`,icon:BarChart3},
 {label:"Training & Development",path:`${base}?workspace=Training+%26+Development`,icon:GraduationCap},
 {label:"HR Reports & Analytics",path:`${base}?workspace=HR+Reports+%26+Analytics`,icon:BarChart3},
 {label:"HR Approvals",path:`${base}?workspace=HR+Approvals`,icon:ShieldCheck},
 {label:"HR Audit & Compliance",path:`${base}?workspace=HR+Audit+%26+Compliance`,icon:ScrollText},
 {label:"HR System Setup",path:`${base}?workspace=System+Setup`,icon:Settings}
];
const payrollItems168=(base)=>[
 {label:"Payroll Dashboard",path:`${base}?workspace=Payroll+Dashboard`,icon:Banknote},
 {label:"Employee Compensation",path:`${base}?workspace=Employee+Compensation`,icon:Landmark},
 {label:"Payroll Inputs",path:`${base}?workspace=Payroll+Inputs`,icon:ReceiptText},
 {label:"Pay Periods",path:`${base}?workspace=Pay+Periods`,icon:CalendarDays},
 {label:"Payroll Runs",path:`${base}?workspace=Payroll+Runs`,icon:WalletCards},
 {label:"Payslips",path:`${base}?workspace=Payslips`,icon:FileText},
 {label:"Payments",path:`${base}?workspace=Payments`,icon:WalletCards},
 {label:"Payroll Reports",path:`${base}?workspace=Payroll+Reports`,icon:BarChart3},
 {label:"Payroll Setup",path:`${base}?workspace=Payroll+Setup`,icon:Settings},
 {label:"Payroll Approvals",path:`${base}?workspace=Payroll+Approvals`,icon:ShieldCheck},
 {label:"Payroll Audit Trail",path:`${base}?workspace=Payroll+Audit+Trail`,icon:ScrollText}
];

const portalItems={
 academic_panel:[["Committees & Results Approvals","/academic-review",ClipboardCheck,true]],
 deputy_access_authority:[["Access Approvals & Reactivation","/access-authority",ShieldCheck,true]],
 auditor:[["Audit & Control Centre","/audit",ShieldCheck,true],["Accounts Reports & Analytics","/audit/reports",BarChart3],["HR Evidence","/audit/hr",Users],["Procurement Evidence","/audit/procurement",Boxes],["Hostel Evidence","/audit/hostel",Building2],["Payroll Evidence","/audit/payroll",Banknote],["Library Evidence","/audit/library",Library]],
 platform_superadmin:[["Technical Dashboard","/platform",LayoutDashboard,true],["Login & Operations Support","/platform?workspace=Support",UserRoundCog],["Access Security & Escalation","/platform?workspace=Security",ShieldCheck],["Updates, Backups & Integrations","/platform?workspace=Maintenance",Settings],["School Module Catalogue","/platform?workspace=Module+Catalogue",BookOpen]],
 registrar:[["Admissions","/admin/admissions",GraduationCap],["Academic Operations","/admin/academic-workspace",BookOpen],["Student Management","/registrar",BookOpen],["Student Search & Lifecycle","/registrar/student-search",Users],["Academic Documents","/registrar/academic-documents",FileText],["Academic Reports","/registrar/reports",BarChart3]],admissions_officer:[["Admissions","/admissions",GraduationCap]],
 finance_officer:[["Accounts Operations","/finance/operations",WalletCards],["Accounts Reports & Analytics","/finance/reports",BarChart3],["My Employee Services","/employee-services",CalendarDays]],hr_officer:[["Human Resources","/hr",UserRoundCog],["My Employee Services","/employee-services",CalendarDays]],procurement_officer:[["Procurement & Supply","/procurement",Boxes],["My Employee Services","/employee-services",CalendarDays]],
 payroll_officer:[["Payroll","/payroll",Banknote],["My Employee Services","/employee-services",CalendarDays]],exam_officer:[["Results & Examinations","/exams",ClipboardCheck],["Committees & Results Approvals","/academic-review",ShieldCheck]],
 librarian:[["Library","/library",Library]],accommodation_officer:[["Accommodation","/accommodation",Building2]],
 communications_officer:[["Communications","/communications",Bell]],
 lecturer:[["Dashboard","/lecturer",LayoutDashboard,true],["My Courses","/lecturer/courses",BookOpen],["My Timetable","/lecturer/timetable",CalendarDays],["Class List","/lecturer/classes",Users],["Attendance","/lecturer/attendance",ClipboardCheck],["Results","/lecturer/results",GraduationCap],["Reports & Teaching History","/lecturer/reports",BarChart3],["Performance & Academic Support","/lecturer/support",BarChart3],["My Employee Services","/lecturer/employee-services",CalendarDays]],
 student:[["Dashboard","/student",LayoutDashboard,true],["Course Registration","/student/registration",BookOpen],["Academic Results","/student/results",ClipboardCheck],["Performance & Academic Support","/student/support",BarChart3],["Academic Record","/student/record",GraduationCap],["Progression","/student/progression",GraduationCap],["Fees & Payments","/student/fees",WalletCards],["Attendance","/student/attendance",CalendarDays],["Profile","/student/profile",Users]],
 staff:[["Staff Portal","/staff",Users]],employee:[["My Employee Services","/employee-services",CalendarDays,true]],parent:[["My Ward","/parent",HeartHandshake]]
};
function platformSelected151(isActive,path,search){if(!isActive||!path.startsWith('/platform'))return isActive;return (new URLSearchParams(search).get('workspace')||'Overview')===(new URLSearchParams(path.split('?')[1]||'').get('workspace')||'Overview')}
function active(path,item){const base=item.path.split("?")[0];return item.exact?path===base:path===base||path.startsWith(base+"/")}
export default function Sidebar({open,onClose}){
 const {currentRole,institutionId}=useUserContext(),{isComplete,loading}=useWorkflow(),location=useLocation(),navigate=useNavigate(),roleCode=currentRole?.code;
 const [hasEmployeeRecord,setHasEmployeeRecord]=useState(false);
 useEffect(()=>{
  let cancelled=false;
  async function checkEmployee(){
   if(!institutionId){if(!cancelled)setHasEmployeeRecord(false);return}
   const {data,error}=await supabase.rpc("unimis_ess_context197",{p_institution_id:institutionId});
   if(!cancelled)setHasEmployeeRecord(!error&&!!data?.employee);
  }
  checkEmployee();
  return()=>{cancelled=true};
 },[institutionId]);
 const groups=useMemo(()=>{
  if(roleCode==="owner")return [...ownerGroups,{key:"owner-hr",label:"Human Resources",items:hrItems168("/owner/hr")},{key:"owner-payroll",label:"Payroll",items:payrollItems168("/owner/payroll")}];
  if(roleCode==="admin")return adminGroups;
  if(roleCode==="registrar")return registrarGroups127;
  if(roleCode==="hr_officer"||roleCode==="hr_manager")return [{key:"hr-workspace",label:"Human Resources",items:hrItems168("/hr")}];
  if(roleCode==="finance_officer"||roleCode==="accountant")return [...financeGroups,{key:"finance-payroll",label:"Payroll",items:payrollItems168("/finance/payroll")}];
  return null;
 },[roleCode]);
 const groupsWithEss=useMemo(()=>{
  if(!groups)return null;
  const cleaned=groups.map(g=>({...g,items:g.items.filter(i=>i.label!=="My Employee Services")}));
  return hasEmployeeRecord?[...cleaned,{key:"my-employee-services",label:"My Employee Services",items:[{label:"My Employee Services",path:"/employee-services",icon:CalendarDays,exact:true}]}]:cleaned;
 },[groups,hasEmployeeRecord]);
 const activeKey=useMemo(()=>groupsWithEss?.find(g=>g.items.some(i=>active(location.pathname,i)))?.key||groupsWithEss?.[0]?.key,[groupsWithEss,location.pathname]);
 const [openGroups,setOpenGroups]=useState({});
 useEffect(()=>{if(activeKey)setOpenGroups(c=>({...c,[activeKey]:true}))},[activeKey]);
 const renderItem=({label,path,icon:Icon,requires,exact})=>{const disabled=roleCode==="admin"&&requires&&(loading||!isComplete(requires)),base=path.split("?")[0],selected=(exact?location.pathname===base:location.pathname===base||location.pathname.startsWith(base+"/"))&&(!path.includes("?")||location.search===`?${path.split("?")[1]}`);return disabled?<div key={label+path} className="nav-link nav-disabled"><Icon size={18}/><span>{label}</span><LockKeyhole size={14}/></div>:<button type="button" key={label+path} onClick={()=>{navigate(path);onClose?.()}} className={`nav-link nav-link-button${selected?" active":""}`}><Icon size={18}/><span>{label}</span></button>};
 return <><button type="button" aria-label="Close navigation" className={open?"sidebar-backdrop show":"sidebar-backdrop"} onClick={onClose}/><aside className={open?"sidebar open":"sidebar"}><div className="sidebar-brand"><div className="brand-badge">U</div><div><strong>UniMIS</strong><small>{currentRole?.name||"Portal"}</small></div><button type="button" className="sidebar-close" onClick={onClose}><X size={20}/></button></div><nav className="sidebar-nav">{groupsWithEss?groupsWithEss.map(g=>{const ex=!!openGroups[g.key];if(g.key==="finance")return <div className="sidebar-menu-group tone-finance" key={g.key}><div className="accounts-finance-heading110">Accounts & Finance</div><AccountsWorkspaceMenu base={roleCode==="admin"?"/admin/finance":"/finance"} onClose={onClose}/>{g.items.filter(i=>i.path.includes("procurement")||i.path.includes("accommodation")||i.path.includes("payroll")).map(renderItem)}</div>;if(g.items.length===1){const i=g.items[0],Icon=i.icon;return <NavLink key={g.key} to={i.path} end={!!i.exact} onClick={onClose} className={({isActive})=>`sidebar-workspace-link tone-${g.tone||"default"}${isActive?" active":""}`}><Icon size={19}/><span>{g.label}</span><ChevronRight size={16}/></NavLink>}return <div className={`sidebar-menu-group tone-${g.tone||"default"}${g.key===activeKey?" active-group":""}`} key={g.key}><button type="button" className="sidebar-group-toggle" onClick={()=>setOpenGroups(c=>({[g.key]:!c[g.key]}))}><span>{g.label}</span>{ex?<ChevronDown size={16}/>:<ChevronRight size={16}/>}</button>{ex&&<div className="sidebar-submenu">{g.items.map(i=><div key={i.path}>{i.heading&&<div className="sidebar-subheading108">{i.heading}</div>}{renderItem(i)}</div>)}</div>}</div>}):(()=>{const base=(portalItems[roleCode]||[["Dashboard","/dashboard",LayoutDashboard]]).filter(([label])=>label!=="My Employee Services");const items=hasEmployeeRecord?[...base,["My Employee Services","/employee-services",CalendarDays]]:base;return items.map(([label,path,icon,exact])=>renderItem({label,path,icon,exact}))})()}</nav></aside></>
}