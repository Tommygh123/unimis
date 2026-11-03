import StudentAttendance140 from './StudentAttendance140';
import {printCurrentView} from "../../lib/printInPlace098";
import {useEffect,useMemo,useState} from "react";

import {useLocation} from "react-router-dom";

import {BookOpen,CalendarDays,ClipboardCheck,Download,GraduationCap,ReceiptText,RefreshCw,Send,UserRoundCheck,WalletCards} from "lucide-react";

import Toast from "../../components/Toast";

import {useConfirm} from "../../contexts/ConfirmContext";

import {loadStudentPortalDashboard,loadStudentGraduationStatus,loadStudentAcademicStanding} from "../../services/studentLifecycle";

import {loadRegistrationSlip,loadRegistrationWorkspace,loadRegistrationHistory,saveCourseSelection,submitRegistration} from "../../services/studentRegistration";

import {studentPublishedResults} from "../../services/results";

import {downloadRegistrationSlipPdf} from "../../lib/registrationPdf";

import "../../styles/portal-professional-058.css";

import "../../styles/portal-professional-058b.css";

import "../../styles/portal-professional-059.css";

import "../../styles/progression-061.css";

import "../../styles/student-progression-062.css";

import "../../styles/progression-064.css";

import {loadStudentProgressionStatus} from "../../services/progression061";

import {loadNextRegistrationReadiness} from "../../services/progression064";

import {loadStudentGpaSummary} from "../../services/gpa069";

import "../../styles/gpa-069.css";

import "../../styles/progression-071.css";
import "../../styles/progression-076.css";
import "../../styles/modules-078.css";
import "../../styles/graduate-portal-090.css";
import {loadStudentFinanceStatement} from "../../services/finance078";


import {printResultSlip,printAcademicTranscript} from "../../lib/academicDocuments094";
import "../../styles/academic-documents-094.css";

const money=(v,c="GHS")=>`${c} ${Number(v||0).toFixed(2)}`;

export default function StudentDashboard(){

 const location=useLocation(),view=location.pathname.split("/")[2]||"dashboard",confirm=useConfirm();

 const [data,setData]=useState(null),[reg,setReg]=useState(null),[results,setResults]=useState(null),[history,setHistory]=useState([]),[progressionStatus,setProgressionStatus]=useState(null),[progressionError,setProgressionError]=useState(""),[nextReadiness,setNextReadiness]=useState(null),[gpaSummary,setGpaSummary]=useState({latest:{},history:[]}),[financeStatement,setFinanceStatement]=useState({summary:{},invoices:[],payments:[]}),[graduation,setGraduation]=useState(null),[academicStanding,setAcademicStanding]=useState(null),[registrationTab,setRegistrationTab]=useState("current"),[selected,setSelected]=useState([]);

 const [loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState(""),[message,setMessage]=useState("");

 async function load(){setLoading(true);setError("");const [a,b,c,h,ps,nr,gs,fs,gr,ast]=await Promise.all([loadStudentPortalDashboard(),loadRegistrationWorkspace(),studentPublishedResults(),loadRegistrationHistory(),loadStudentProgressionStatus(),loadNextRegistrationReadiness(),loadStudentGpaSummary(),loadStudentFinanceStatement(),loadStudentGraduationStatus(),loadStudentAcademicStanding()]);if(a.error)setError(a.error.message);else setData(a.data);if(b.error)setError(b.error.message);else{setReg(b.data);setSelected((b.data?.courses||[]).filter(x=>x.selected).map(x=>x.course_offering_id).filter(Boolean))}if(c.error)setError(c.error.message);else setResults(c.data);if(h.error)setError(h.error.message);else setHistory(h.data||[]);if(ps.error){setProgressionError(ps.error.message||String(ps.error));setProgressionStatus(null)}else{setProgressionError("");setProgressionStatus(ps.data&&Object.keys(ps.data).length?ps.data:null);}if(!nr.error)setNextReadiness(nr.data||null);if(!gs.error)setGpaSummary(gs.data||{latest:{},history:[]});if(!fs.error)setFinanceStatement(fs.data||{summary:{},invoices:[],payments:[]});if(!gr.error)setGraduation(gr.data&&Object.keys(gr.data).length?gr.data:null);if(!ast.error)setAcademicStanding(ast.data&&Object.keys(ast.data).length?ast.data:null);setLoading(false)}

 useEffect(()=>{load()},[]);

 const courses=reg?.courses||[],status=reg?.period_registration?.registration_status||"draft",editable=["draft","rejected"].includes(status),offered=courses.filter(c=>c.course_offering_id);

 const totalCredits=offered.filter(c=>selected.includes(c.course_offering_id)).reduce((a,c)=>a+Number(c.credit_hours||0),0);

 const resultRows=useMemo(()=>Array.isArray(results)?results:(results?.results||results?.students||results?.courses||[]),[results]);

 const currentPeriodName=reg?.academic_period?.name||data?.period_registration?.academic_period||"";

 const currentYearName=reg?.academic_year?.name||data?.period_registration?.academic_year||"";
 const currentResults=useMemo(()=>resultRows.filter(x=>(!currentPeriodName||(x.academic_period||x.period_name||"")===currentPeriodName)&&(!currentYearName||x.academic_year===currentYearName)),[resultRows,currentPeriodName,currentYearName]);

 const recordGroups=useMemo(()=>{const grouped={};for(const x of resultRows){const key=[x.academic_year,x.academic_period||x.period_name||"Published Results"].filter(Boolean).join(" • ");(grouped[key]??=[]).push(x)}return Object.entries(grouped)},[resultRows]);

 const s=data?.student||{},e=data?.enrolment||{},r=data?.period_registration||{},f=data?.finance||{};
 const isGraduated=graduation?.decision==="graduated";
 const displayCgpa=isGraduated?(graduation?.cgpa??gpaSummary.latest?.cgpa):gpaSummary.latest?.cgpa;

 function toggle(c){if(!editable||!c.course_offering_id||(c.is_required&&reg?.policy?.auto_select_required_courses!==false))return;setSelected(v=>v.includes(c.course_offering_id)?v.filter(x=>x!==c.course_offering_id):[...v,c.course_offering_id])}

 async function save(){setBusy(true);const x=await saveCourseSelection(reg.period_registration.id,selected);x.error?setError(x.error.message):(setMessage("Course selection saved."),await load());setBusy(false)}

 async function submit(){if(!(await confirm({title:"Submit semester registration?",message:`Submit ${totalCredits} credits for ${reg?.academic_period?.name}?`,confirmLabel:"Submit registration"})))return;setBusy(true);const x=await submitRegistration(reg.period_registration.id);x.error?setError(x.error.message):(setMessage("Registration submitted successfully."),await load());setBusy(false)}

 async function pdf(id=reg?.period_registration?.id){if(!id)return;const x=await loadRegistrationSlip(id);x.error?setError(x.error.message):downloadRegistrationSlipPdf(x.data)}

 if(loading)return <div className="portal-058"><div className="portal-loading">Loading student workspace…</div></div>;

 const title={dashboard:"Dashboard",registration:"Course Registration",results:"Academic Results",record:"Academic Record",fees:"Fees & Payments",attendance:"Attendance",profile:"Student Profile"}[view]||"Dashboard";

 const ResultsTable=({rows=resultRows})=> <div className="responsive-table"><table><thead><tr><th>Course</th><th>Period</th><th>Score</th><th>Grade</th><th>GP</th><th>Status</th></tr></thead><tbody>{rows.map((x,i)=><tr key={x.course_result_id||x.id||i}><td><strong>{x.course_code||x.code||"—"}</strong><small>{x.course_name||x.name||""}</small></td><td>{x.academic_period||x.period_name||"—"}</td><td>{x.total_score??x.score??"—"}{x.total_score!=null||x.score!=null?"%":""}</td><td>{x.letter_grade||x.grade||"—"}</td><td>{x.grade_point??x.gp??"—"}</td><td><span className="status-pill verified">Published</span></td></tr>)}{!rows.length&&<tr><td colSpan="6" className="table-empty">No published results are available for this view.</td></tr>}</tbody></table></div>;

 return <div className="portal-058 student-portal-058"><Toast message={error||message} type={error?"error":"success"} onClose={()=>{setError("");setMessage("")}}/>

  <header className="portal-hero"><div><span className="section-kicker">STUDENT PORTAL</span><h1>{title}</h1><p>{view==="dashboard"?(isGraduated?`Welcome, ${s.first_name||"Student"}. Your programme is complete. Your graduation and award summary is shown below.`:`Welcome, ${s.first_name||"Student"}. Your academic workspace at a glance.`):"Official student self-service and academic information."}</p></div><button className="secondary-action" onClick={load}><RefreshCw size={16}/>Refresh</button></header>

  {view==="dashboard"&&<>
   {isGraduated&&<section className="graduate-banner-090"><div><span className="section-kicker">PROGRAMME COMPLETED</span><h2>Congratulations, {s.first_name||"Student"}</h2><p>Your official graduation outcome and award classification are recorded in UniMIS.</p></div><span className="graduate-status-090"><GraduationCap size={20}/> Graduated</span></section>}
   {!isGraduated&&progressionError&&<section className="progression-status-card progression-diagnostic-card"><span className="section-kicker">ACADEMIC PROGRESSION</span><h3>Progression information unavailable</h3><p>{progressionError}</p></section>}
   {!isGraduated&&progressionStatus&&<section className="progression-status-card"><span className="section-kicker">ACADEMIC PROGRESSION</span><h3>{progressionStatus.decision==="promoted"?`Progressed to Level ${progressionStatus.proposed_level}`:progressionStatus.decision==="repeat"?`Repeat Level ${progressionStatus.from_level}`:progressionStatus.decision==="probation"?`Academic Probation — Level ${progressionStatus.from_level}`:progressionStatus.decision==="deferred"?"Progression Deferred":progressionStatus.decision.replaceAll("_"," ")}</h3><p>{progressionStatus.academic_year} progression decision</p></section>}
   {!isGraduated&&academicStanding&&<section className={`academic-standing-093 ${academicStanding.kind==="completion_exception"?"standing-danger":"standing-warning"}`}><div><span className="section-kicker">ACADEMIC STANDING</span><h2>{academicStanding.title}</h2><p>{academicStanding.message}</p></div><div className="standing-metrics-093"><span><b>{academicStanding.outstanding_courses||0}</b> outstanding course(s)</span><span><b>{academicStanding.outstanding_credits||0}</b> trail credits</span></div>{academicStanding.trails?.length>0&&<div className="standing-trails-093">{academicStanding.trails.map(t=><span key={t.course_code}><b>{t.course_code}</b> — {t.course_name} ({t.credit_hours} credits)</span>)}</div>}</section>}
   <div className="portal-kpis portal-kpis-090">
    <article className="tone-blue"><GraduationCap/><span>Student Number</span><strong>{s.student_number||"—"}</strong></article>
    <article className="tone-indigo"><BookOpen/><span>Programme</span><strong>{e.programme_code||graduation?.programme_code||"—"}</strong><small>{e.programme_name||graduation?.programme_name}</small></article>
    <article className="tone-sky"><UserRoundCheck/><span>{isGraduated?"Final Level":"Level"}</span><strong>{graduation?.final_level||e.current_level||"—"}</strong><small>{isGraduated?"Completed":e.enrolment_status}</small></article>
    <article className="tone-amber"><ClipboardCheck/><span>{isGraduated?"Credits Completed":"Published Results"}</span><strong>{isGraduated?`${graduation?.credits_earned??0}/${graduation?.credits_required??"—"}`:resultRows.length}</strong></article>
    <article className="tone-violet cgpa-kpi"><GraduationCap/><span>{isGraduated?"Final CGPA":"Current CGPA"}</span><strong>{displayCgpa??"—"}</strong><small>{isGraduated?(graduation?.award_classification||"Final academic standing"):(gpaSummary.latest?.academic_year?`${gpaSummary.latest.academic_year} • ${gpaSummary.latest.academic_period}`:"Calculated from published results")}</small></article>
    <article className="tone-green finance"><WalletCards/><span>Fee Balance</span><strong>{money(f.balance,f.currency)}</strong></article>
   </div>
   {isGraduated&&<section className="graduate-award-card-090"><div className="section-title"><div><span className="section-kicker">GRADUATION & AWARD</span><h2>{graduation.award_classification||"Award classification"}</h2><p>{graduation.programme_code} — {graduation.programme_name}</p></div><GraduationCap size={36}/></div><div className="graduate-detail-grid-090"><div><span>Academic status</span><strong>Graduated</strong></div><div><span>Final CGPA</span><strong>{graduation.cgpa??"—"}</strong></div><div><span>Classification</span><strong>{graduation.award_classification||"—"}</strong></div><div><span>Credits completed</span><strong>{graduation.credits_earned??0}/{graduation.credits_required??"—"}</strong></div><div><span>Graduation date</span><strong>{graduation.graduation_date||"—"}</strong></div><div><span>Outstanding trails</span><strong>{graduation.outstanding_trails??0}</strong></div></div></section>}
   {!isGraduated&&<div className="portal-two portal-two-090"><section className="management-card registration-card-090"><div className="section-title"><div><h2>Latest Registration</h2><p>{isGraduated?"Historical registration record. Your final programme level is shown above.":"Most recently approved/created semester registration. Your current academic level is shown above."}</p></div></div><div className="detail-grid"><div><span>Academic year</span><strong>{r.academic_year||"—"}</strong></div><div><span>Academic period</span><strong>{r.academic_period||"—"}</strong></div><div><span>Status</span><strong>{r.registration_status||"Not created"}</strong></div><div><span>Registered level</span><strong>{r.level_number||e.current_level||"—"}</strong></div></div>{isGraduated&&<p className="historical-note-090">This is your latest registration record; it does not replace your final Level {graduation.final_level||e.current_level} completion status.</p>}</section><section className="management-card results-card-090"><div className="section-title"><div><h2>Latest Academic Results</h2><p>Only officially published course results appear here.</p></div></div><ResultsTable/></section></div>}
 </>}

  {view==="registration"&&<section className="management-card"><div className="section-title"><div><h2>Course Registration</h2><p>Register for the active semester or retrieve previous registrations.</p></div><div className="portal-tabs"><button className={registrationTab==="current"?"active":""} onClick={()=>setRegistrationTab("current")}>Current Registration</button><button className={registrationTab==="history"?"active":""} onClick={()=>setRegistrationTab("history")}>Registration History</button></div></div>{registrationTab==="current"?<><div className="registration-current-head"><span className="section-kicker">ACTIVE ACADEMIC PERIOD</span><h3>{reg?.academic_period?.name||"Current Semester"}</h3><p>{reg?.academic_year?.name} • Level {reg?.enrolment?.current_level} • <strong>{status}</strong></p></div><div className="registration-policy-strip"><span><small>Credits</small><strong>{totalCredits} / {reg?.policy?.max_credits??24}</strong></span><span><small>Fee clearance</small><strong>{reg?.fee_clearance?.required?(reg?.fee_clearance?.cleared?"Cleared":"Not cleared"):"Not required"}</strong></span></div><div className="responsive-table"><table><thead><tr><th></th><th>Course</th><th>Category</th><th>Credits</th><th>Offering</th></tr></thead><tbody>{courses.map(c=><tr key={c.programme_course_id}><td><input type="checkbox" checked={Boolean(c.course_offering_id&&selected.includes(c.course_offering_id))} disabled={!editable||!c.course_offering_id||(c.is_required&&reg?.policy?.auto_select_required_courses!==false)} onChange={()=>toggle(c)}/></td><td><strong>{c.course_code}</strong><small>{c.course_name}</small></td><td>{c.is_required?"Required":c.course_category}</td><td>{c.credit_hours}</td><td>{c.course_offering_id?`Section ${c.section_code||"A"}`:"No offering"}</td></tr>)}</tbody></table></div><div className="registration-actions"><button className="secondary-button" disabled={busy||!editable} onClick={save}>Save Draft</button><button className="primary-button" disabled={busy||!editable||!selected.length} onClick={submit}><Send size={16}/>Submit Registration</button><button className="secondary-button" disabled={!reg?.period_registration?.id} onClick={()=>pdf()}><Download size={16}/>Registration Slip PDF</button></div></>:<div className="registration-history-list">{history.map(h=><article className="registration-history-card" key={h.period_registration_id}><div className="registration-history-head"><div><span>{h.academic_year}</span><h3>{h.academic_period}</h3><p>Level {h.level_number||"—"} • {h.course_count} courses • {h.credits} credits</p></div><div><span className={`status-pill ${h.registration_status==="approved"?"verified":""}`}>{h.registration_status}</span><button className="secondary-action" onClick={()=>pdf(h.period_registration_id)}><Download size={15}/>Slip PDF</button></div></div><div className="responsive-table"><table><thead><tr><th>Course</th><th>Credits</th><th>Section</th><th>Status</th></tr></thead><tbody>{(h.courses||[]).map(c=><tr key={c.course_registration_id}><td><strong>{c.course_code}</strong><small>{c.course_name}</small></td><td>{c.credit_hours}</td><td>{c.section_code||"A"}</td><td>{c.status}</td></tr>)}</tbody></table></div></article>)}{!history.length&&<div className="portal-empty"><BookOpen/><strong>No registration history yet</strong><span>Previous semester registrations will remain here after new academic periods are opened.</span></div>}</div>}</section>}

  {view==="results"&&<section className="management-card academic-doc-section-094"><div className="section-title"><div><h2>Academic Results</h2><p>Official published results for {currentPeriodName||"the current academic period"}.</p></div><div className="academic-doc-actions-094"><button className="secondary-action" onClick={()=>printResultSlip({student:s,enrolment:e,period:r,results:currentResults,gpa:gpaSummary.latest,institution:data?.institution})}><Download size={16}/> Result Slip / PDF</button></div></div><ResultsTable rows={currentResults}/></section>}

  {view==="record"&&<section className="management-card"><div className="section-title"><div><h2>Academic Record</h2><p>Your cumulative published course history, semester GPA and running CGPA.</p></div><div className="academic-doc-actions-094"><button className="primary-button" onClick={()=>printAcademicTranscript({student:s,enrolment:e,results:resultRows,gpaSummary,graduation,institution:data?.institution})}><Download size={16}/> Transcript / PDF</button></div></div><div className="academic-summary-strip"><div><span>{isGraduated?"Final CGPA":"Current CGPA"}</span><strong>{displayCgpa??"—"}</strong></div><div><span>Latest Semester GPA</span><strong>{gpaSummary.latest?.gpa??"—"}</strong></div><div><span>Credits Earned</span><strong>{gpaSummary.latest?.earned_credits??0}</strong></div><div><span>Credits Attempted</span><strong>{gpaSummary.latest?.attempted_credits??0}</strong></div></div><div className="gpa-history-grid">{(gpaSummary.history||[]).map((g,i)=><article key={`${g.academic_year}-${g.academic_period}-${i}`}><span>{g.academic_year} • {g.academic_period}</span><strong>GPA {g.gpa??"—"}</strong><small>Running CGPA {g.cgpa??"—"} • {g.earned_credits}/{g.attempted_credits} credits earned</small></article>)}</div>{recordGroups.length?recordGroups.map(([period,periodRows])=><div className="record-period" key={period}><div className="record-period-head"><div><span>ACADEMIC PERIOD</span><h3>{period}</h3></div><div><strong>{periodRows.length}</strong><small>Published courses</small></div></div><ResultsTable rows={periodRows}/></div>):<div className="table-empty">No published academic history is available yet.</div>}</section>}

  {view==="progression"&&<section className="management-card student-progression-page">

   <div className="section-title"><div><span className="section-kicker">STUDENT LIFECYCLE</span><h2>Academic Progression</h2><p>Your official end-of-year progression outcome and academic standing.</p></div><GraduationCap/></div>

   {progressionStatus?<>

    <div className="progression-student-hero">

     <div><span>Academic Year Reviewed</span><strong>{progressionStatus.academic_year}</strong></div>

     <div><span>Previous Level</span><strong>Level {progressionStatus.from_level}</strong></div>

     <div><span>Official Outcome</span><strong>{progressionStatus.decision==="promoted"?`Progressed to Level ${progressionStatus.proposed_level}`:progressionStatus.decision==="repeat"?`Remain at Level ${progressionStatus.from_level}`:progressionStatus.decision.replaceAll("_"," ")}</strong></div>

    </div>

    <div className="progression-student-summary"><h3>{progressionStatus.decision==="promoted"?"Progression Confirmed":"Official Progression Decision"}</h3><p>{progressionStatus.decision==="promoted"?`Your progression to Level ${progressionStatus.proposed_level} has been finalized by the university.`:progressionStatus.decision==="repeat"?`You will remain at Level ${progressionStatus.from_level} for the next academic cycle.`:progressionStatus.decision==="probation"?`You will remain under academic probation at Level ${progressionStatus.from_level}.`:progressionStatus.decision==="deferred"?"Your academic progression has been deferred.":"This is your finalized academic progression decision."}</p>{progressionStatus.reason&&<div className="progression-reason"><strong>Decision reason</strong><span>{progressionStatus.reason}</span></div>}

     {progressionStatus.decision==="promoted"&&(progressionStatus.failed_courses||[]).length>0&&<div className="carryover-box"><strong>Outstanding / Carry-over Courses</strong>{progressionStatus.failed_courses.map((c,i)=><div key={i}>{c.course_code} — {c.course_name||""} ({c.credits} credits)</div>)}</div>}

     <div className="progression-metrics"><span><small>Credits Earned</small><strong>{progressionStatus.credits_earned??"—"}</strong></span><span><small>Failed Credits</small><strong>{progressionStatus.failed_credits??0}</strong></span><span><small>Failed Courses</small><strong>{progressionStatus.courses_failed??0}</strong></span></div>

    </div>

    {progressionStatus.decision==="promoted"&&nextReadiness&&<div className={`registration-readiness ${nextReadiness.ready?"ready":"pending"}`}><h3>Next Registration Readiness</h3><p><strong>{nextReadiness.ready?"Ready":"Pending setup"}</strong> — {nextReadiness.reason}</p>{nextReadiness.next_academic_year&&<p>{nextReadiness.next_academic_year} • {nextReadiness.next_period||"Semester pending"} • Level {nextReadiness.current_level}</p>}{nextReadiness.ready&&<p>{nextReadiness.offering_count} course offering(s) available for registration.</p>}</div>}

   </>:progressionError?<div className="portal-empty progression-diagnostic"><GraduationCap/><strong>Progression information could not be loaded</strong><span>{progressionError}</span><small>The finalized database decision has not been changed. This message identifies the portal retrieval error.</small></div>:<div className="portal-empty"><GraduationCap/><strong>No finalized progression decision yet</strong><span>Your official progression outcome will appear here after the university completes the end-of-year progression exercise.</span></div>}

  </section>}

  {view==="fees"&&<><div className="portal-kpis compact"><article><ReceiptText/><span>Total Billed</span><strong>{money(financeStatement.summary?.billed,"GHS")}</strong></article><article><WalletCards/><span>Total Paid</span><strong>{money(financeStatement.summary?.paid,"GHS")}</strong></article><article className="finance"><ReceiptText/><span>Outstanding Balance</span><strong>{money(financeStatement.summary?.balance,"GHS")}</strong></article></div><section className="management-card"><div className="section-title"><div><h2>Student Statement</h2><p>Your official invoices and payments.</p></div><button className="secondary-button" onClick={()=>printCurrentView("UniMIS StudentDashboard Report")}>Print / Save PDF</button></div><div className="responsive-table"><table><thead><tr><th>Invoice</th><th>Date</th><th>Due</th><th>Total</th><th>Paid</th><th>Balance</th><th>Status</th></tr></thead><tbody>{(financeStatement.invoices||[]).map((x,i)=><tr key={i}><td>{x.invoice_number}</td><td>{x.invoice_date}</td><td>{x.due_date||"—"}</td><td>{money(x.total_amount,x.currency_code)}</td><td>{money(x.amount_paid,x.currency_code)}</td><td>{money(x.balance,x.currency_code)}</td><td>{x.status}</td></tr>)}</tbody></table></div><h3>Payments</h3><div className="responsive-table"><table><thead><tr><th>Reference</th><th>Date</th><th>Method</th><th>Amount</th><th>Status</th></tr></thead><tbody>{(financeStatement.payments||[]).map((x,i)=><tr key={i}><td>{x.payment_reference}</td><td>{new Date(x.payment_date).toLocaleString()}</td><td>{x.payment_method}</td><td>{money(x.amount,x.currency_code)}</td><td>{x.status}</td></tr>)}</tbody></table></div></section></>}

  {view==="attendance"&&<StudentAttendance140/>}

  {view==="profile"&&<section className="management-card"><div className="section-title"><div><h2>Student Profile</h2><p>Official academic identity and enrolment.</p></div></div><div className="detail-grid"><div><span>Student Number</span><strong>{s.student_number||"—"}</strong></div><div><span>Name</span><strong>{[s.first_name,s.middle_name,s.last_name].filter(Boolean).join(" ")}</strong></div><div><span>Programme</span><strong>{e.programme_code||"—"} — {e.programme_name||""}</strong></div><div><span>Level</span><strong>{e.current_level||"—"}</strong></div><div><span>Status</span><strong>{e.enrolment_status||"—"}</strong></div></div></section>}

 </div>

}