import {useCallback,useEffect,useState} from 'react';
import {Link} from 'react-router-dom';
import {supabase} from '../../lib/supabase';
import {useUserContext} from '../../contexts/UserContext';
import {schoolModules127,ownerFinance127} from '../../lib/schoolModules127';
import '../../styles/school-dashboard-127.css';
export default function SchoolDashboard127({role}){
 const {institutionId,profile}=useUserContext();const [data,setData]=useState(null),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 const load=useCallback(async()=>{if(!institutionId)return;setBusy(true);setError('');try{const r=await supabase.rpc('unimis_school_dashboard127',{p_inst:institutionId,p_workspace:role});if(r.error)throw r.error;setData(r.data);}catch(e){setError(e.message)}finally{setBusy(false)}},[institutionId,role]);useEffect(()=>{load()},[load]);
 const modules=schoolModules127(role);const cards=[['Students','students'],['Applications','applications'],['Programmes','programmes'],['Course Offerings','offerings'],['Active Users','users']];
 return <section className="school-dashboard127"><div className="page-heading"><span className="eyebrow">{role==='owner'?'School Owner':'Registrar'} · Dashboard</span><h1>Welcome, {profile?.display_name||'School officer'}</h1><p>{data?.year||'Academic year not selected'} · {data?.semester||'Semester not selected'}</p><button className="primary-action" disabled={busy} onClick={load}>{busy?'Refreshing…':'Refresh dashboard'}</button></div>{error&&<p role="alert" className="notice-panel">{error}</p>}
 <div className="portal-grid">{cards.map(([label,key])=><article className="portal-card" key={key}><span>{label}</span><strong>{data?Number(data[key]||0).toLocaleString():'—'}</strong><p>School total</p></article>)}</div>
 {role==='owner'&&data?.finance&&<div className="portal-grid">{[['Net student collections','collected'],['Outstanding fees','outstanding']].map(([label,key])=><article className="portal-card" key={key}><span>{label} · GHS</span><strong>{Number(data.finance[key]||0).toLocaleString(undefined,{minimumFractionDigits:2,maximumFractionDigits:2})}</strong><p>All academic years · completed payments only</p></article>)}</div>}
 <h2>School Operations & Reports</h2><div className="action-grid">{modules.map(([title,text,to,planned])=><Link className="action-card" to={to} key={title}><div><h3>{title}</h3><p>{text}</p><span>{planned?'Workspace overview →':'Open workspace →'}</span></div></Link>)}</div>
 {role==='owner'&&<><h2>Accounts, Finance & Governance</h2><div className="action-grid">{ownerFinance127.map(([title,text,to])=><Link className="action-card" to={to} key={title}><div><h3>{title}</h3><p>{text}</p><span>Open workspace →</span></div></Link>)}</div><p><Link to="/owner/audit">Open Audit Logs</Link></p></>}
 </section>;
}
