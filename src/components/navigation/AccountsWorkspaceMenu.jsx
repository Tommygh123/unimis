import {useState} from 'react';
import {NavLink,useLocation} from 'react-router-dom';
import {ChevronDown,ChevronRight,WalletCards,BarChart3} from 'lucide-react';
import {operationSections,reportSections} from '../../lib/accountsNavigation';
import '../../styles/accounts-workspaces.css';
export default function AccountsWorkspaceMenu({base,onClose}){
 const location=useLocation(),inReports=location.pathname.endsWith('/reports');
 const [expanded,setExpanded]=useState(null);
 const selected=expanded??(location.pathname.startsWith(base+'/')?(inReports?'reports':'operations'):'');
 const query=new URLSearchParams(location.search);
 return <div className="accounts-menu110">{[['operations','Accounts Operations',WalletCards,operationSections,'tab'],['reports','Accounts Reports & Analytics',BarChart3,reportSections,'report']].map(([key,label,Icon,sections,param])=><div className="accounts-menu-branch110" key={key}><button type="button" aria-expanded={selected===key} className={`accounts-menu-heading110 ${location.pathname===`${base}/${key}`?'selected':''}`} onClick={()=>setExpanded(selected===key?'':key)}><Icon size={16}/><span>{label}</span>{selected===key?<ChevronDown size={14}/>:<ChevronRight size={14}/>}</button>{selected===key&&<div className="accounts-menu-pages110">{sections.map(([id,title])=><NavLink key={id} to={`${base}/${key}?${param}=${id}`} onClick={onClose} className={`accounts-menu-page110${location.pathname===`${base}/${key}`&&(query.get(param)||'dashboard')===id?' active':''}`}>{title}</NavLink>)}</div>}</div>)}</div>
}
