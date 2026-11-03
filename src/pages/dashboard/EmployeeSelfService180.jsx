import React,{useEffect,useMemo,useState} from 'react'
import {CalendarDays,Clock3,FileText,UserRound,WalletCards,Send,RefreshCw} from 'lucide-react'
import {supabase} from '../../lib/supabase'
import {useUserContext} from '../../contexts/UserContext'
import './EmployeeSelfService180.css'

const fmt=d=>d?new Date(d).toLocaleDateString():'—'
export default function EmployeeSelfService180(){
 const{institutionId}=useUserContext()
 const[me,setMe]=useState(null),[attendance,setAttendance]=useState([]),[leaves,setLeaves]=useState([]),[types,setTypes]=useState([]),[payslips,setPayslips]=useState([]),[loading,setLoading]=useState(true),[msg,setMsg]=useState('')
 const[form,setForm]=useState({leave_type_id:'',start_date:'',end_date:'',reason:''})
 async function load(){
  setLoading(true);setMsg('')
  const{data:{user}}=await supabase.auth.getUser()
  if(!user||!institutionId){setLoading(false);return}
  const{data,error}=await supabase.rpc('unimis_ess_context197',{p_institution_id:institutionId})
  if(error){setMsg(error.message);setLoading(false);return}
  const e=data?.employee||null
  setMe(e)
  if(!e){setMsg(`Your UniMIS staff account is active, but it is not yet linked to an Employee Master record. HR should ensure the employee record uses ${user.email}; UniMIS will then link the account automatically.`);setLoading(false);return}
  setAttendance(data?.attendance||[]);setLeaves(data?.leaves||[]);setTypes(data?.leave_types||[]);setPayslips(data?.payslips||[])
  setLoading(false)
 }
 useEffect(()=>{load()},[institutionId])
 const today=attendance.find(x=>x.work_date===new Date().toISOString().slice(0,10))
 const pending=leaves.filter(x=>['submitted','pending'].includes(x.status)).length
 async function submitLeave(e){
  e.preventDefault()
  if(!me||!form.leave_type_id||!form.start_date||!form.end_date||!form.reason.trim()){setMsg('Complete the leave type, dates and reason.');return}
  if(form.end_date<form.start_date){setMsg('End date cannot be before start date.');return}
  const{error}=await supabase.rpc('unimis_ess_submit_leave197',{p_institution_id:institutionId,p_leave_type_id:form.leave_type_id,p_start_date:form.start_date,p_end_date:form.end_date,p_reason:form.reason.trim()})
  if(error){setMsg(error.message);return}
  setMsg('Leave request submitted successfully. It is now awaiting HR approval.')
  setForm({leave_type_id:'',start_date:'',end_date:'',reason:''});load()
 }
 if(loading)return <div className="ess180"><h1>My Employee Services</h1><p>Loading your HR record…</p></div>
 return <div className="ess180">
  <div className="essHero"><div><span>EMPLOYEE SELF-SERVICE</span><h1>My Employee Services</h1><p>Use your phone, tablet or computer to manage your own HR services.</p></div>{me&&<div className="essIdentity"><strong>{me.first_name} {me.last_name}</strong><small>{me.employee_no}</small></div>}</div>
  {msg&&<div className="essNotice">{msg}</div>}
  {!me?<section className="essPanel"><h2>Employee account not linked</h2><p>Your UniMIS login is valid. Employee Self-Service becomes available when this account is linked to your Employee Master record. Ask HR to confirm that your employee record uses the same email address.</p></section>:<>
   <div className="essCards">
    <div><Clock3/><small>Today</small><strong>{today?.status||'No attendance yet'}</strong></div>
    <div><CalendarDays/><small>Pending leave</small><strong>{pending}</strong></div>
    <div><FileText/><small>Leave requests</small><strong>{leaves.length}</strong></div>
    <div><WalletCards/><small>Payslips</small><strong>{payslips.length}</strong></div>
   </div>
   <section className="essPanel"><div className="essTitle"><div><h2>My Profile</h2><p>Your employee master information.</p></div><UserRound/></div>
    <div className="essGrid"><div><small>Employee no.</small><strong>{me.employee_no}</strong></div><div><small>Email</small><strong>{me.email||'—'}</strong></div><div><small>Phone</small><strong>{me.phone||'—'}</strong></div><div><small>Employment</small><strong>{me.employment_status||'—'}</strong></div><div><small>Hire date</small><strong>{me.hire_date||'—'}</strong></div></div>
   </section>
   <section className="essPanel"><div className="essTitle"><div><h2>Request Leave</h2><p>Submit from your phone and track the decision here.</p></div><Send/></div>
    <form className="essForm" onSubmit={submitLeave}><label>Leave type<select value={form.leave_type_id} onChange={e=>setForm({...form,leave_type_id:e.target.value})}><option value="">Select leave type</option>{types.map(x=><option key={x.id} value={x.id}>{x.name}</option>)}</select></label><label>From<input type="date" value={form.start_date} onChange={e=>setForm({...form,start_date:e.target.value})}/></label><label>To<input type="date" value={form.end_date} onChange={e=>setForm({...form,end_date:e.target.value})}/></label><label className="wide">Reason<textarea value={form.reason} onChange={e=>setForm({...form,reason:e.target.value})} placeholder="Reason for leave"/></label><button>Submit leave request</button></form>
   </section>
   <section className="essPanel"><div className="essTitle"><div><h2>My Leave Requests</h2><p>Submitted, approved and rejected requests.</p></div><RefreshCw onClick={load}/></div><div className="essTable"><table><thead><tr><th>Dates</th><th>Reason</th><th>Status</th><th>Decision</th></tr></thead><tbody>{leaves.length?leaves.map(x=><tr key={x.id}><td>{x.start_date} → {x.end_date}</td><td>{x.reason}</td><td><b>{x.status}</b></td><td>{x.decision_notes||'—'}</td></tr>):<tr><td colSpan="4">No leave requests yet.</td></tr>}</tbody></table></div></section>
   <section className="essPanel"><div className="essTitle"><div><h2>My Attendance</h2><p>Your recent attendance and punctuality record.</p></div><Clock3/></div><div className="essTable"><table><thead><tr><th>Date</th><th>Check in</th><th>Check out</th><th>Status</th><th>Late</th></tr></thead><tbody>{attendance.length?attendance.map(x=><tr key={x.id}><td>{x.work_date}</td><td>{x.check_in?new Date(x.check_in).toLocaleTimeString():'—'}</td><td>{x.check_out?new Date(x.check_out).toLocaleTimeString():'—'}</td><td>{x.status}</td><td>{x.late_minutes||0} min</td></tr>):<tr><td colSpan="5">No attendance records yet.</td></tr>}</tbody></table></div></section>
  </>}
 </div>
}