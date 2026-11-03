import {useEffect,useMemo,useState} from "react";
import {Link} from "react-router-dom";
import {CheckCircle2,CreditCard,Download,FileText,GraduationCap,LogIn,LogOut,Plus,RefreshCw,School,Send,Upload,UserPlus,Pencil,Trash2,X,Eye,EyeOff} from "lucide-react";
import {useAuth} from "../../contexts/AuthContext";
import Toast from "../../components/Toast";
import {useConfirm} from "../../contexts/ConfirmContext";
import {classifyPortalAccount,portalMismatchMessage} from "../../lib/portalAccess";
import {downloadAdmissionLetterPdf,downloadApplicationReceiptPdf} from "../../lib/admissionPdfs";
import {loadPublicWebsite} from "../../services/publicWebsite";
import {
 addApplicantExamQualification,addApplicantQualification,applicantSignIn,applicantSignUp,createApplicantApplication,
 initializeApplicantPaystackPayment,loadApplicantDashboard,loadApplicantPortalBootstrap,
 respondToApplicantOffer,saveApplicantPortalProfile,submitApplicantApplication,
 uploadApplicantDocument,verifyApplicantPaystackPayment,updateApplicantExamQualification,updateApplicantQualification,
 deleteApplicantQualification,deleteApplicantDocument,updateApplicantApplicationChoices
} from "../../services/applicantPortal";
import "./ApplicantPortalEnhancements.css";
const profile0={first_name:"",middle_name:"",last_name:"",date_of_birth:"",gender:"",phone:"",
 nationality:"Ghanaian",country_of_residence:"Ghana",country_of_birth:"Ghana",address:"",city:"",
 region:"",applicant_category:"local",national_id_type:"Ghana Card",national_id_number:"",
 passport_number:"",passport_expiry_date:"",residency_status:""};
const WASSCE_SUBJECTS=[
 "English Language","Core Mathematics","Integrated Science","Social Studies",
 "Elective Mathematics","Physics","Chemistry","Biology","General Agriculture",
 "Economics","Geography","Government","History","Literature in English",
 "Accounting","Business Management","Cost Accounting","Financial Accounting",
 "French","ICT","Technical Drawing","Building Construction","Woodwork",
 "Metalwork","Auto Mechanics","Applied Electricity","Electronics"
];
const WASSCE_GRADES=["A1","B2","B3","C4","C5","C6","D7","E8","F9"];
const SUBJECT_ALIASES={
 "english":"English Language","english language":"English Language","english_language":"English Language",
 "core maths":"Core Mathematics","core math":"Core Mathematics","core mathematics":"Core Mathematics","mathematics core":"Core Mathematics","mathematics (core)":"Core Mathematics","core_mathematics":"Core Mathematics",
 "integrated science":"Integrated Science","science integrated":"Integrated Science","science (integrated)":"Integrated Science","integrated_science":"Integrated Science",
 "social studies":"Social Studies","social_studies":"Social Studies",
 "elective maths":"Elective Mathematics","elective math":"Elective Mathematics","elective mathematics":"Elective Mathematics","mathematics elective":"Elective Mathematics","mathematics (elective)":"Elective Mathematics","elective_mathematics":"Elective Mathematics",
 "general agriculture":"General Agriculture","general_agriculture":"General Agriculture",
 "literature":"Literature in English","literature in english":"Literature in English","literature_in_english":"Literature in English",
 "ict":"ICT","information communication technology":"ICT","information and communication technology":"ICT"
};
function displaySubjectName(value){
 const raw=String(value||"").trim();
 if(!raw)return "";
 const key=raw.toLowerCase().replace(/[-_]+/g," ").replace(/\s+/g," ").trim();
 const aliased=SUBJECT_ALIASES[key];
 if(aliased)return aliased;
 const exact=WASSCE_SUBJECTS.find(x=>x.toLowerCase()===key);
 return exact||raw;
}
const examRows0=()=>[
 {subject:"English Language",grade:"",is_core:true},
 {subject:"Core Mathematics",grade:"",is_core:true},
 {subject:"Integrated Science",grade:"",is_core:true},
 {subject:"",grade:"",is_core:false},
 {subject:"",grade:"",is_core:false},
 {subject:"",grade:"",is_core:false},
];
const qual0={qualification_type:"WASSCE",institution_name:"",examining_body:"WAEC",index_number:"",
 completion_year:"",exam_sitting:"May/June",overall_result:"",subject_results:"",exam_results:examRows0()};

const cash=(a,c="GHS")=>{try{return new Intl.NumberFormat("en-GH",{style:"currency",currency:c}).format(Number(a||0));}catch{return `${c} ${Number(a||0).toFixed(2)}`;}};
function Pill({value}){return <span className={`applicant-status applicant-status-${value||"draft"}`}>{(value||"draft").replaceAll("_"," ")}</span>;}

export default function ApplicantPortal(){
 const {user,session,signOut}=useAuth();
 const confirmAction=useConfirm();
 const [boot,setBoot]=useState(null),[mine,setMine]=useState(null),[loading,setLoading]=useState(true);
 const [accessBlocked,setAccessBlocked]=useState(null);
 const [publicBrand,setPublicBrand]=useState(null);
 const [busy,setBusy]=useState(false),[message,setMessage]=useState(""),[error,setError]=useState(""),[mode,setMode]=useState("login");

 async function refresh(){
  setLoading(true);setError("");
  const [b,w]=await Promise.all([loadApplicantPortalBootstrap(),loadPublicWebsite()]);
  if(b.error){setError(b.error.message);setLoading(false);return;}
  setBoot(b.data);if(!w.error)setPublicBrand(w.data?.settings||null);
  if(session?.user){
   const access=await classifyPortalAccount(session.user);
   if(["staff","student","parent","lookup_error"].includes(access.kind)){setMine(null);setAccessBlocked({kind:access.kind,message:portalMismatchMessage(access.kind,"applicant")});}
   else{setAccessBlocked(null);const d=await loadApplicantDashboard();if(d.error)setError(d.error.message);else setMine(d.data);}
  }else{setMine(null);setAccessBlocked(null);}
  setLoading(false);
 }
 useEffect(()=>{refresh();},[session?.user?.id]);

 useEffect(()=>{
  const q=new URLSearchParams(window.location.search),ref=q.get("reference")||q.get("trxref");
  if(q.get("payment")!=="callback"||!ref||!session?.user)return;
  (async()=>{setBusy(true);const r=await verifyApplicantPaystackPayment(ref);
   if(r.error)setError(r.error.message);else setMessage("Payment verified successfully.");
   window.history.replaceState({},"","/apply");await refresh();setBusy(false);
  })();
 },[session?.user?.id]);

 if(loading)return <div className="applicant-portal"><div className="applicant-loading">Loading admissions portal…</div></div>;
 const baseInst=boot?.institution||{},inst={...baseInst,name:publicBrand?.display_name||baseInst.name,short_name:publicBrand?.short_name||baseInst.short_name},cycles=boot?.cycles||[];
 return <div className="applicant-portal">
  <header className="applicant-public-header">
   <div className="applicant-brand">{inst?.logo_url?<img src={inst.logo_url} alt=""/>:<div className="applicant-logo"><School/></div>}
    <div><strong>{inst?.short_name||inst?.name||"UniMIS"}</strong><span>Online Admissions Portal</span></div>
   </div>
   <div className="applicant-header-actions"><Link className="applicant-link-button" to="/">Admissions Home</Link>{user?<><span className="applicant-user-email">{user.email}</span><button className="applicant-link-button" onClick={()=>signOut()}><LogOut size={16}/>Sign out</button></>:<Link className="applicant-link-button" to="/login">University Portal</Link>}</div>
  </header>
  <main className="applicant-public-main">
   <section className="applicant-hero"><div><span className="applicant-eyebrow">Admissions</span><h1>Apply to {inst?.name||"our university"}</h1><p>Create one applicant account, complete your application, pay securely, submit and track your decision online.</p></div><div className="applicant-hero-stat"><GraduationCap/><strong>{cycles.length}</strong><span>Open admission {cycles.length===1?"cycle":"cycles"}</span></div></section>
   <Toast message={error||message} type={error?"error":"success"} onClose={()=>{setError("");setMessage("")}}/>
   {accessBlocked?<section className="applicant-panel applicant-wide-panel applicant-access-denied"><h2>Wrong portal for this account</h2><p>{accessBlocked.message}</p><div className="applicant-offer-actions">{accessBlocked.kind==="student"?<Link className="applicant-primary" to="/student-login">Go to Student Portal</Link>:<Link className="applicant-primary" to="/login">Go to Staff & Lecturer Portal</Link>}<button className="applicant-secondary" onClick={()=>signOut()}>Sign out</button></div></section>
    :!user?<Guest boot={boot} mode={mode} setMode={setMode} busy={busy} setBusy={setBusy} setMessage={setMessage} setError={setError} signOut={signOut}/>
    :!mine?.applicant?<Profile inst={inst} busy={busy} setBusy={setBusy} setMessage={setMessage} setError={setError} done={refresh}/>
    :<Workspace boot={boot} mine={mine} busy={busy} setBusy={setBusy} setMessage={setMessage} setError={setError} refresh={refresh} confirmAction={confirmAction}/>}
  </main>
 </div>;
}

function Guest({boot,mode,setMode,busy,setBusy,setMessage,setError,signOut}){
 const [showPassword,setShowPassword]=useState(false);
 const [f,setF]=useState({fullName:"",email:localStorage.getItem("unimis_applicant_login_email")||"",password:""});
 const [remember,setRemember]=useState(()=>Boolean(localStorage.getItem("unimis_applicant_login_email")));
 async function submit(e){e.preventDefault();setBusy(true);setError("");setMessage("");
  if(mode==="login"){if(remember)localStorage.setItem("unimis_applicant_login_email",f.email.trim());else localStorage.removeItem("unimis_applicant_login_email");}
  const r=mode==="signup"?await applicantSignUp(f):await applicantSignIn(f.email,f.password);
  if(r.error)setError(r.error.message);
  else if(mode==="signup"&&!r.data?.session){setMessage("Account created. Check your email to confirm it, then sign in.");setMode("login");}
  else if(mode==="login"&&r.data?.user){const access=await classifyPortalAccount(r.data.user);if(access.kind!=="applicant"&&access.kind!=="unknown"){await signOut();setError(portalMismatchMessage(access.kind,"applicant"));}else setMessage("Signed in successfully.");}
  else setMessage("Signed in successfully.");
  setBusy(false);
 }
 return <div className="applicant-two-column">
  <section className="applicant-panel"><div className="applicant-panel-heading">{mode==="signup"?<UserPlus/>:<LogIn/>}<div><h2>{mode==="signup"?"Create applicant account":"Applicant sign in"}</h2><p>This account is only for admissions.</p></div></div>
   <form className="applicant-form" onSubmit={submit}>{mode==="signup"&&<label>Full name<input required value={f.fullName} onChange={e=>setF({...f,fullName:e.target.value})}/></label>}<label>Email<input required type="email" value={f.email} onChange={e=>setF({...f,email:e.target.value})}/></label><label>Password<div className="applicant-password-wrap"><input required type={showPassword?"text":"password"} minLength="8" value={f.password} onChange={e=>setF({...f,password:e.target.value})}/><button type="button" className="applicant-password-toggle" onClick={()=>setShowPassword(v=>!v)} aria-label={showPassword?"Hide password":"Show password"} title={showPassword?"Hide password":"Show password"}>{showPassword?<EyeOff size={18}/>:<Eye size={18}/>}</button></div></label>{mode==="login"&&<><label className="applicant-remember"><input type="checkbox" checked={remember} onChange={e=>setRemember(e.target.checked)}/><span>Remember me</span></label><small className="applicant-remember-note">Your password is never stored in the browser.</small></>}<button className="applicant-primary" disabled={busy}>{busy?"Please wait…":mode==="signup"?"Create account":"Sign in"}</button></form>
   <button type="button" className="applicant-switch" onClick={()=>setMode(mode==="signup"?"login":"signup")}>{mode==="signup"?"Already have an applicant account? Sign in":"First time applying? Create an account"}</button>
  </section>
  <section className="applicant-panel"><div className="applicant-panel-heading"><School/><div><h2>Open admissions</h2><p>Select your route after signing in.</p></div></div><div className="applicant-cycle-list">{(boot?.cycles||[]).map(c=><div className="applicant-cycle-card" key={c.id}><strong>{c.name}</strong><span>{c.admission_level} • {c.applicant_scope==="both"?"Local & International":c.applicant_scope}</span><small>{c.max_programme_choices} programme choice{c.max_programme_choices===1?"":"s"} allowed</small></div>)}{!boot?.cycles?.length&&<p>No admission cycle is currently open.</p>}</div></section>
 </div>;
}

function Profile({inst,busy,setBusy,setMessage,setError,done}){
 const [f,setF]=useState(profile0),set=k=>e=>setF({...f,[k]:e.target.value});
 async function submit(e){e.preventDefault();setBusy(true);setError("");setMessage("");const r=await saveApplicantPortalProfile({...f,institution_id:inst.id});if(r.error)setError(r.error.message);else{setMessage("Applicant profile saved.");await done();}setBusy(false);}
 return <section className="applicant-panel applicant-wide-panel"><div className="applicant-panel-heading"><UserPlus/><div><h2>Complete your applicant profile</h2><p>Choose local or international before starting an application.</p></div></div><form className="applicant-form" onSubmit={submit}><div className="applicant-form-grid">
  <label>Applicant category<select value={f.applicant_category} onChange={set("applicant_category")}><option value="local">Local applicant</option><option value="international">International applicant</option></select></label>
  <label>Nationality<input required value={f.nationality} onChange={set("nationality")}/></label>
  <label>First name<input required value={f.first_name} onChange={set("first_name")}/></label><label>Middle name<input value={f.middle_name} onChange={set("middle_name")}/></label>
  <label>Last name<input required value={f.last_name} onChange={set("last_name")}/></label><label>Date of birth<input type="date" value={f.date_of_birth} onChange={set("date_of_birth")}/></label>
  <label>Gender<select value={f.gender} onChange={set("gender")}><option value="">Select…</option><option value="female">Female</option><option value="male">Male</option><option value="other">Other</option></select></label><label>Phone<input value={f.phone} onChange={set("phone")}/></label>
  <label>Country of residence<input value={f.country_of_residence} onChange={set("country_of_residence")}/></label><label>Country of birth<input value={f.country_of_birth} onChange={set("country_of_birth")}/></label>
  {f.applicant_category==="local"?<><label>ID type<input value={f.national_id_type} onChange={set("national_id_type")}/></label><label>National ID number<input value={f.national_id_number} onChange={set("national_id_number")}/></label></>:<><label>Passport number<input required value={f.passport_number} onChange={set("passport_number")}/></label><label>Passport expiry<input type="date" value={f.passport_expiry_date} onChange={set("passport_expiry_date")}/></label></>}
  <label>Region / State<input value={f.region} onChange={set("region")}/></label><label>City<input value={f.city} onChange={set("city")}/></label>
 </div><label>Address<textarea rows="2" value={f.address} onChange={set("address")}/></label><button className="applicant-primary" disabled={busy}>Save profile & continue</button></form></section>;
}

function Workspace({boot,mine,busy,setBusy,setMessage,setError,refresh,confirmAction}){
 const a=mine.applicant,apps=mine.applications||[],qualificationCount=(mine.qualifications||[]).length;
 const editable=apps.every(x=>["draft","incomplete","returned"].includes((x.status||"").toLowerCase())&&!['paid','verified'].includes((x.payment_status||"").toLowerCase()));
 const [newOpen,setNewOpen]=useState(!apps.length),[activeId,setActiveId]=useState(()=>apps.find(x=>["draft","incomplete","returned"].includes((x.status||"").toLowerCase()))?.id||apps[0]?.id||null);
 useEffect(()=>{if(!activeId&&apps.length)setActiveId(apps[0].id);},[apps.length,activeId]);
 const active=apps.find(x=>x.id===activeId)||apps[0];
 const status=(active?.status||"draft").toLowerCase(),isDraft=["draft","incomplete","returned"].includes(status);
 const offers=apps.flatMap(x=>x.offers||[]),pendingOffer=offers.find(o=>(o.response_status||"pending")==="pending");
 return <>
  <section className="applicant-dashboard-banner">
   <div><span className="applicant-eyebrow">Applicant Dashboard</span><h2>Welcome, {a.first_name}</h2><p>{isDraft?"You have an application in progress. You can sign out and continue it later from this dashboard.":active?"Track your submitted application and admission decision here.":"Start an application when you are ready."}</p></div>
   {active&&<div className="applicant-dashboard-state"><span>Current application</span><strong>{active.application_number||"Draft application"}</strong><Pill value={active.status}/></div>}
  </section>

  <section className="applicant-summary">
   <div><span>Applicant</span><strong>{a.first_name} {a.last_name}</strong><small>{a.applicant_category} • {a.nationality}</small></div>
   <div><span>Applications</span><strong>{apps.length}</strong><small>All admission cycles</small></div>
   <div><span>Qualifications</span><strong>{qualificationCount}</strong><small>Academic records</small></div>
   <button className="applicant-primary" onClick={()=>setNewOpen(!newOpen)}><Plus size={16}/>{newOpen?"Close":"New application"}</button>
  </section>

  {active&&<section className="applicant-continue-card">
   <div><span className="applicant-eyebrow">{active.cycle?.name}</span><h3>{isDraft?"Continue your application":"Application tracking"}</h3><p>{isDraft?"Your saved draft is stored in UniMIS. Continue from where you stopped.":pendingOffer?"An admission offer is awaiting your response.":"Your application has been submitted. Follow its status here."}</p></div>
   <button className="applicant-primary" onClick={()=>{setActiveId(active.id);document.getElementById(`application-${active.id}`)?.scrollIntoView({behavior:"smooth",block:"start"});}}>{isDraft?"Continue application":"View status"}</button>
  </section>}

  <ApplicantProfileSummary applicant={a} inst={boot?.institution} editable={editable} hasApplications={apps.length>0} busy={busy} setBusy={setBusy} setMessage={setMessage} setError={setError} refresh={refresh}/>
  {newOpen&&<NewApplication boot={boot} applicant={a} busy={busy} setBusy={setBusy} setMessage={setMessage} setError={setError} done={async()=>{setNewOpen(false);await refresh();}}/>}
  <Qualifications rows={mine.qualifications||[]} subjectResults={mine.subject_results||[]} editable={editable} busy={busy} setBusy={setBusy} setMessage={setMessage} setError={setError} refresh={refresh} confirmAction={confirmAction}/>

  <section className="applicant-applications">
   <div className="applicant-section-title"><div><h2>My applications</h2><p>Draft applications can be continued later. Submitted applications become read-only for review.</p></div><button className="applicant-secondary" onClick={refresh}><RefreshCw size={15}/>Refresh</button></div>
   {apps.map(app=><Application key={app.id} app={app} boot={boot} applicant={a} qualifications={mine.qualifications||[]} qualificationCount={qualificationCount} subjectResults={mine.subject_results||[]} busy={busy} setBusy={setBusy} setMessage={setMessage} setError={setError} refresh={refresh} confirmAction={confirmAction}/>)}
   {!apps.length&&<div className="applicant-empty">No application yet. Choose <strong>New application</strong>.</div>}
  </section>
 </>;
}


function ApplicantProfileSummary({applicant,inst,editable,hasApplications,busy,setBusy,setMessage,setError,refresh}){
 const [editing,setEditing]=useState(false);
 const [f,setF]=useState({...profile0,...applicant});
 useEffect(()=>{if(!editing)setF({...profile0,...applicant});},[applicant?.id,editing]);
 const set=k=>e=>setF({...f,[k]:e.target.value});
 async function save(e){
  e.preventDefault();setBusy(true);setError("");setMessage("");
  const r=await saveApplicantPortalProfile({...f,institution_id:inst?.id||applicant.institution_id});
  if(r.error)setError(r.error.message);else{setMessage("Applicant profile updated.");setEditing(false);await refresh();}
  setBusy(false);
 }
 return <section className="applicant-panel applicant-wide-panel applicant-edit-card">
  <div className="applicant-section-title"><div><h2>Applicant profile</h2><p>Review your personal information before payment and submission.</p></div>
   {editable&&!editing&&<button className="applicant-secondary" onClick={()=>setEditing(true)}><Pencil size={15}/>Edit profile</button>}
   {editing&&<button className="applicant-secondary" onClick={()=>setEditing(false)}><X size={15}/>Cancel</button>}
  </div>
  {!editable&&<div className="applicant-lock-note">Profile editing is locked because an application has been paid or submitted. Contact Admissions if a correction is required.</div>}
  {!editing?<div className="applicant-profile-view">
    <div><span>Full name</span><strong>{[applicant.first_name,applicant.middle_name,applicant.last_name].filter(Boolean).join(" ")}</strong></div>
    <div><span>Date of birth</span><strong>{applicant.date_of_birth||"—"}</strong></div>
    <div><span>Gender</span><strong>{applicant.gender||"—"}</strong></div>
    <div><span>Phone</span><strong>{applicant.phone||"—"}</strong></div>
    <div><span>Nationality</span><strong>{applicant.nationality||"—"}</strong></div>
    <div><span>Applicant category</span><strong>{applicant.applicant_category||"—"}</strong></div>
    <div><span>Residence</span><strong>{[applicant.city,applicant.region,applicant.country_of_residence].filter(Boolean).join(", ")||"—"}</strong></div>
    <div><span>ID / Passport</span><strong>{applicant.national_id_number||applicant.passport_number||"—"}</strong></div>
   </div>:
   <form className="applicant-form applicant-inline-form" onSubmit={save}>
    <div className="applicant-form-grid">
     <label>First name<input required value={f.first_name||""} onChange={set("first_name")}/></label>
     <label>Middle name<input value={f.middle_name||""} onChange={set("middle_name")}/></label>
     <label>Last name<input required value={f.last_name||""} onChange={set("last_name")}/></label>
     <label>Date of birth<input type="date" value={f.date_of_birth||""} onChange={set("date_of_birth")}/></label>
     <label>Gender<select value={f.gender||""} onChange={set("gender")}><option value="">Select…</option><option value="female">Female</option><option value="male">Male</option><option value="other">Other</option></select></label>
     <label>Phone<input value={f.phone||""} onChange={set("phone")}/></label>
     <label>Nationality<input value={f.nationality||""} onChange={set("nationality")}/></label>
     <label>Country of residence<input value={f.country_of_residence||""} onChange={set("country_of_residence")}/></label>
     <label>City<input value={f.city||""} onChange={set("city")}/></label>
     <label>Region<input value={f.region||""} onChange={set("region")}/></label>
     <label>Applicant category<select disabled={hasApplications} value={f.applicant_category||"local"} onChange={set("applicant_category")} title={hasApplications?"Applicant category is fixed once an application has been created.":""}><option value="local">Local</option><option value="international">International</option></select></label>
     <label>National ID type<input value={f.national_id_type||""} onChange={set("national_id_type")}/></label>
     <label>National ID number<input value={f.national_id_number||""} onChange={set("national_id_number")}/></label>
     <label>Passport number<input value={f.passport_number||""} onChange={set("passport_number")}/></label>
    </div>
    <label>Address<textarea rows="2" value={f.address||""} onChange={set("address")}/></label>
    <button className="applicant-primary" disabled={busy}>Save profile changes</button>
   </form>}
 </section>;
}

function NewApplication({boot,applicant,busy,setBusy,setMessage,setError,done}){
 const cycles=(boot.cycles||[]).filter(c=>c.applicant_scope==="both"||c.applicant_scope===applicant.applicant_category);
 const [cycleId,setCycleId]=useState(cycles[0]?.id||""),[choices,setChoices]=useState([""]);
 const cycle=cycles.find(c=>c.id===cycleId);
 const programmes=useMemo(()=>(boot.programmes||[]).filter(p=>{
  if(!cycle)return false;if(cycle.admission_level!=="both"&&p.admission_level!==cycle.admission_level)return false;
  if(applicant.applicant_category==="local"&&p.accepts_local===false)return false;
  if(applicant.applicant_category==="international"&&p.accepts_international===false)return false;return true;
 }),[boot.programmes,cycle,applicant.applicant_category]);
 useEffect(()=>setChoices([""]),[cycleId]);
 async function submit(e){e.preventDefault();const ids=choices.filter(Boolean);if(new Set(ids).size!==ids.length){setError("Programme choices must be different.");return;}setBusy(true);setError("");setMessage("");const r=await createApplicantApplication({admissionCycleId:cycleId,programmeIds:ids});if(r.error)setError(r.error.message);else{setMessage("Draft application created.");await done();}setBusy(false);}
 return <section className="applicant-panel applicant-wide-panel"><div className="applicant-panel-heading"><GraduationCap/><div><h2>Start a new application</h2><p>{applicant.applicant_category} applicant</p></div></div><form className="applicant-form" onSubmit={submit}>
  <label>Admission cycle<select required value={cycleId} onChange={e=>setCycleId(e.target.value)}><option value="">Select…</option>{cycles.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
  {choices.map((x,i)=><label key={i}>Programme choice {i+1}<select required value={x} onChange={e=>{const n=[...choices];n[i]=e.target.value;setChoices(n);}}><option value="">Select programme…</option>{programmes.map(p=><option key={p.id} value={p.id}>{p.code} — {p.name}</option>)}</select></label>)}
  {cycle&&choices.length<cycle.max_programme_choices&&<button type="button" className="applicant-secondary" onClick={()=>setChoices([...choices,""])}><Plus size={15}/>Add another choice</button>}
  <button className="applicant-primary" disabled={busy||!cycleId}>Create draft application</button>
 </form></section>;
}

function Qualifications({rows,subjectResults=[],editable,busy,setBusy,setMessage,setError,refresh,confirmAction}){
 const [open,setOpen]=useState(false),[editingId,setEditingId]=useState(null),[f,setF]=useState(qual0),set=k=>e=>setF(prev=>({...prev,[k]:e.target.value}));
 const structured=(f.qualification_type||"").toUpperCase()==="WASSCE";
 function setExamRow(index,key,value){setF(prev=>{const next=[...(prev.exam_results||[])];next[index]={...next[index],[key]:value};return {...prev,exam_results:next};});}
 function addExamRow(){setF(prev=>({...prev,exam_results:[...(prev.exam_results||[]),{subject:"",grade:"",is_core:false}]}));}
 function removeExamRow(index){setF(prev=>{const next=(prev.exam_results||[]).filter((_,i)=>i!==index);return {...prev,exam_results:next.length?next:examRows0()};});}
 function beginAdd(){setEditingId(null);setF({...qual0,exam_results:examRows0()});setOpen(true);}
 function beginEdit(q){
  const embedded=Array.isArray(q.subject_results)?q.subject_results:[];
  const fallback=subjectResults.filter(r=>String(r.qualification_id)===String(q.id));
  const source=embedded.length?embedded:fallback;
  const results=source.map(r=>({
   subject:displaySubjectName(r.subject_name||r.subject_key||r.subject),
   grade:String(r.grade||"").toUpperCase(),
   is_core:Boolean(r.is_core)
  }));
  const nextForm={
   ...qual0,...q,
   qualification_type:q.qualification_type||"WASSCE",
   institution_name:q.institution_name||"",
   examining_body:q.examining_body||((q.qualification_type||"").toUpperCase()==="WASSCE"?"WAEC":""),
   index_number:q.index_number||"",
   completion_year:q.completion_year||q.exam_year||"",
   exam_sitting:q.exam_sitting||q.details?.exam_sitting||"May/June",
   overall_result:q.overall_result||"",
   subject_results:q.details?.subject_results||"",
   exam_results:results.length?results:examRows0()
  };
  setEditingId(q.id);
  setF(nextForm);
  setOpen(true);
 }
 async function submit(e){
  e.preventDefault();setBusy(true);setError("");setMessage("");
  let r;
  if(structured){
   const subjects=(f.exam_results||[]).filter(x=>x.subject&&x.grade);
   if(subjects.length<6){setError("Enter at least six WASSCE subject results for this sitting.");setBusy(false);return;}
   if(new Set(subjects.map(x=>x.subject.toLowerCase())).size!==subjects.length){setError("Each subject should appear only once in an examination sitting.");setBusy(false);return;}
   r=editingId?await updateApplicantExamQualification({...f,id:editingId,subject_results:subjects}):await addApplicantExamQualification({...f,subject_results:subjects});
  }else r=editingId?await updateApplicantQualification({...f,id:editingId}):await addApplicantQualification(f);
  if(r.error)setError(r.error.message);else{setMessage(editingId?"Qualification updated. Eligibility has been recalculated from the corrected data.":structured?"Structured examination results saved. Verification will be completed by Admissions.":"Qualification added.");setOpen(false);setEditingId(null);setF({...qual0,exam_results:examRows0()});await refresh();}setBusy(false);
 }
 async function remove(q){
  if(!(await confirmAction({title:"Delete qualification?",message:`Delete ${q.qualification_type} qualification? This cannot be undone.`,confirmLabel:"Delete",tone:"danger"})))return;
  setBusy(true);setError("");const r=await deleteApplicantQualification(q.id);
  if(r.error)setError(r.error.message);else{setMessage("Qualification deleted.");await refresh();}
  setBusy(false);
 }
 return <section className="applicant-panel applicant-wide-panel"><div className="applicant-section-title"><div><h2>Academic qualifications</h2><p>Review and correct your qualifications before payment. After payment/submission, they are locked for Admissions review.</p></div>{editable&&<button type="button" className="applicant-secondary" onClick={beginAdd}><Plus size={15}/>Add qualification</button>}</div>
  {!editable&&<div className="applicant-lock-note">Qualification editing is locked after payment or submission.</div>}
  <div className="applicant-qualification-list">{rows.map(q=>{const embedded=Array.isArray(q.subject_results)?q.subject_results:[];const results=embedded.length?embedded:subjectResults.filter(r=>String(r.qualification_id)===String(q.id));return <div className="applicant-qualification-card" key={q.id}>
   <div className="applicant-qualification-head"><div><strong>{q.qualification_type}</strong><span>{q.examining_body||q.institution_name||"Qualification"}{q.completion_year?` • ${q.completion_year}`:""}{q.exam_sitting?` • ${q.exam_sitting}`:""}{q.index_number?` • Index ${q.index_number}`:""}</span></div>
    <div className="applicant-edit-actions">{(q.qualification_type||"").toUpperCase()==="WASSCE"&&<small className={`qualification-verification ${q.verification_status||"unverified"}`}>{(q.verification_status||"unverified").replaceAll("_"," ")}</small>}{editable&&<><button type="button" className="applicant-icon-action" title="Edit qualification" onClick={()=>beginEdit(q)}><Pencil size={15}/></button><button type="button" className="applicant-icon-action danger" title="Delete qualification" onClick={()=>remove(q)}><Trash2 size={15}/></button></>}</div>
   </div>
   {!!results.length&&<div className="applicant-result-view">{results.map(r=><span key={r.id}><b>{r.subject_name}</b> {r.grade}</span>)}</div>}
  </div>})}</div>
  {!rows.length&&<div className="applicant-empty">No academic qualification has been added yet.</div>}
  {open&&<form className="applicant-form applicant-inline-form applicant-edit-form" onSubmit={submit}>
   <div className="applicant-section-title"><div><h3>{editingId?"Edit qualification":"Add qualification"}</h3><p>{editingId?"Correct the saved details below. Any previous verification will be reset because the result changed.":"Enter examination details exactly as they appear on the official record."}</p></div><button type="button" className="applicant-secondary" onClick={()=>{setOpen(false);setEditingId(null);}}><X size={15}/>Close</button></div>
   <div className="applicant-form-grid">
    <label>Qualification type<select required value={f.qualification_type} onChange={set("qualification_type")}><option value="WASSCE">WASSCE</option><option value="SSSCE">SSSCE</option><option value="Diploma">Diploma</option><option value="HND">HND</option><option value="BSc">Bachelor's degree</option><option value="MSc">Master's degree</option><option value="Other">Other</option></select></label>
    <label>Institution / School<input value={f.institution_name||""} onChange={set("institution_name")}/></label>
    <label>Examining body<input value={f.examining_body||""} onChange={set("examining_body")} disabled={structured}/></label>
    <label>Index / Student number<input required={structured} value={f.index_number||""} onChange={set("index_number")}/></label>
    <label>{structured?"Examination year":"Completion year"}<input required={structured} type="number" min="1980" max="2100" value={f.completion_year||""} onChange={set("completion_year")}/></label>
    {structured?<label>Examination sitting<select value={f.exam_sitting||"May/June"} onChange={set("exam_sitting")}><option>May/June</option><option>Nov/Dec</option><option>Private Candidate</option><option>School Candidate</option><option>Other</option></select></label>:<label>Overall result / class<input value={f.overall_result||""} onChange={set("overall_result")}/></label>}
   </div>
   {structured?<div className="structured-results-entry">
    <div className="structured-results-head"><div><h4>Subject results</h4><p>These structured grades drive automatic programme eligibility.</p></div><button type="button" className="applicant-secondary" onClick={addExamRow}><Plus size={14}/>Add subject</button></div>
    <div className="structured-results-table">{(f.exam_results||[]).map((row,i)=><div className="structured-result-row" key={i}>
     <label>Subject<select value={row.subject} onChange={e=>setExamRow(i,"subject",e.target.value)}><option value="">Select subject…</option>{row.subject&&!WASSCE_SUBJECTS.includes(row.subject)&&<option value={row.subject}>{row.subject}</option>}{WASSCE_SUBJECTS.map(subject=><option value={subject} key={subject}>{subject}</option>)}</select></label>
     <label>Grade<select value={row.grade} onChange={e=>setExamRow(i,"grade",e.target.value)}><option value="">Grade…</option>{WASSCE_GRADES.map(grade=><option value={grade} key={grade}>{grade}</option>)}</select></label>
     <label className="structured-core-toggle"><input type="checkbox" checked={Boolean(row.is_core)} onChange={e=>setExamRow(i,"is_core",e.target.checked)}/>Core</label>
     <button type="button" className="structured-remove" title="Remove subject" onClick={()=>removeExamRow(i)}>×</button>
    </div>)}</div>
    <div className="applicant-muted">Eligibility is recalculated automatically. WAEC verification remains a separate verification step.</div>
   </div>:<label>Subject results / additional details<textarea rows="3" value={f.subject_results||""} onChange={set("subject_results")}/></label>}
   <button className="applicant-primary" disabled={busy}>{editingId?"Save qualification changes":"Save qualification"}</button>
  </form>}
 </section>;
}

function Application({app,boot,applicant,qualifications=[],qualificationCount=0,subjectResults=[],busy,setBusy,setMessage,setError,refresh,confirmAction}){
 const [files,setFiles]=useState({}),[editingChoices,setEditingChoices]=useState(false),[choiceIds,setChoiceIds]=useState(()=>app.choices?.map(c=>c.programme?.id).filter(Boolean)||[]),[extraDocLabel,setExtraDocLabel]=useState(""),[extraDocFile,setExtraDocFile]=useState(null),draft=["draft","incomplete","returned"].includes((app.status||"").toLowerCase());
 const reqs=(boot.document_requirements||[]).filter(r=>r.admission_cycle_id===app.admission_cycle_id&&["both",app.applicant_category].includes(r.applicant_category)&&["both",app.admission_level].includes(r.admission_level)&&(!r.programme_id||app.choices?.some(c=>c.programme?.id===r.programme_id)));
 const uploaded=new Set((app.documents||[]).map(d=>d.document_type?.toLowerCase())),missing=reqs.filter(r=>r.is_required&&!uploaded.has(r.document_type.toLowerCase()));
 const first=app.choices?.[0]?.programme?.id,fee=(boot.fee_rules||[]).filter(f=>f.admission_cycle_id===app.admission_cycle_id&&f.applicant_category===app.applicant_category&&f.admission_level===app.admission_level&&(!f.programme_id||f.programme_id===first)).sort((a,b)=>(a.programme_id?0:1)-(b.programme_id?0:1))[0];
 const paid=["paid","not_required"].includes(app.payment_status),hasQualification=qualificationCount>0,documentsComplete=missing.length===0,prePaymentComplete=draft&&hasQualification&&documentsComplete,ready=prePaymentComplete&&paid;
 const availableProgrammes=(boot.programmes||[]).filter(p=>(app.admission_level==="both"||p.admission_level===app.admission_level||p.admission_level==="both")&&(app.applicant_category!=="local"||p.accepts_local!==false)&&(app.applicant_category!=="international"||p.accepts_international!==false));
 async function saveChoices(){const ids=choiceIds.filter(Boolean);if(!ids.length){setError("Select at least one programme.");return;}if(new Set(ids).size!==ids.length){setError("Programme choices must be different.");return;}setBusy(true);setError("");const r=await updateApplicantApplicationChoices(app.id,ids);if(r.error)setError(r.error.message);else{setMessage("Programme choices updated. Eligibility and fee requirements have been recalculated.");setEditingChoices(false);await refresh();}setBusy(false);}
 async function upload(r){const file=files[r.document_type];if(!file){setError(`Choose ${r.display_name} first.`);return;}setBusy(true);setError("");const x=await uploadApplicantDocument({institutionId:app.institution_id,applicationId:app.id,documentType:r.document_type,file});if(x.error)setError(x.error.message);else{setMessage(`${r.display_name} uploaded.`);setFiles({...files,[r.document_type]:null});await refresh();}setBusy(false);}
 async function removeDocument(row,label){if(!(await confirmAction({title:"Remove document?",message:`Remove ${label}? You can upload a corrected copy before payment.`,confirmLabel:"Remove",tone:"danger"})))return;setBusy(true);setError("");const x=await deleteApplicantDocument(row);if(x.error)setError(x.error.message);else{setMessage(`${label} removed.`);await refresh();}setBusy(false);}
 async function uploadExtraDocument(){
  const label=extraDocLabel.trim();
  if(!label){setError("Enter a name for the additional document.");return;}
  if(!extraDocFile){setError("Choose a file for the additional document.");return;}
  const cleanLabel=label.replace(/\s+/g," ").slice(0,80);
  const documentType=`Additional - ${cleanLabel}`;
  setBusy(true);setError("");
  const x=await uploadApplicantDocument({institutionId:app.institution_id,applicationId:app.id,documentType,file:extraDocFile});
  if(x.error)setError(x.error.message);
  else{
    setMessage(`${cleanLabel} added to your application.`);
    setExtraDocLabel("");
    setExtraDocFile(null);
    await refresh();
  }
  setBusy(false);
 }
 async function replaceDocument(r,row){const file=files[r.document_type];if(!file){setError(`Choose the replacement ${r.display_name} first.`);return}setBusy(true);setError("");try{const x=await uploadApplicantDocument({institutionId:app.institution_id,applicationId:app.id,documentType:r.document_type,file,replaceDocument:row});if(x.error)setError(x.error.message);else{setMessage(`${r.display_name} replaced.`);setFiles({...files,[r.document_type]:null});await refresh()}}finally{setBusy(false)}}
 async function pay(){setBusy(true);setError("");const r=await initializeApplicantPaystackPayment(app.id);if(r.error)setError(r.error.message);else{const url=r.data?.authorization_url||r.data?.data?.authorization_url;if(url)window.location.assign(url);else setError("Payment gateway did not return an authorization URL.");}setBusy(false);}
 async function submit(){setBusy(true);setError("");try{const r=await submitApplicantApplication(app.id);if(r.error){setError(r.error.message);return;}setMessage("Application submitted successfully. Download your application confirmation below.");await refresh();const latest=await loadApplicantDashboard();const submitted=latest.data?.applications?.find(x=>x.id===app.id);if(submitted?.submitted_at)downloadApplicationReceiptPdf({institution:boot?.institution,applicant,application:submitted,qualifications,subjectResults});}catch(e){setError(e.message||"Unable to download confirmation. Use the download button to retry.");}finally{setBusy(false);}}
 async function respond(o,response){const accepting=response==="accepted";const okay=await confirmAction({title:accepting?"Accept admission offer?":"Decline admission offer?",message:accepting?`Accept offer ${o.offer_number}? Your application will be marked admitted.`:`Decline offer ${o.offer_number}? This response will be recorded.`,confirmLabel:accepting?"Accept offer":"Decline offer",tone:accepting?"primary":"danger"});if(!okay)return;setBusy(true);setError("");setMessage("");const r=await respondToApplicantOffer(o.id,response);if(r.error)setError(r.error.message);else{setMessage(accepting?"Offer accepted successfully. Your admission status is now admitted.":"Offer declined. Your response has been recorded.");await refresh();}setBusy(false);}
 const completedSteps=[Boolean(app.choices?.length),hasQualification,documentsComplete,paid,!draft].filter(Boolean).length,progress=Math.round((completedSteps/5)*100); return <article id={`application-${app.id}`} className="applicant-application-card">
  <div className="applicant-application-head"><div><span className="applicant-eyebrow">{app.cycle?.name}</span><h3>{app.application_number}</h3><p>{app.applicant_category} • {app.admission_level}</p></div><div className="applicant-status-stack"><Pill value={app.status}/><Pill value={app.decision_status}/></div></div>
  <div className="applicant-progress-summary"><div><span>Application progress</span><strong>{progress}%</strong></div><div className="applicant-progress-bar"><i style={{width:`${progress}%`}}/></div><small>{draft?"Draft saved automatically as each section is completed. You can return later.":"Application submitted — tracking mode."}</small></div>
  <div className="applicant-progress-grid"><div className={app.choices?.length?"done":""}><CheckCircle2/><strong>Programme choices</strong><span>{app.choices?.map(c=>c.programme?.code).join(", ")}</span></div><div className={hasQualification?"done":""}><GraduationCap/><strong>Qualification</strong><span>{hasQualification?`${qualificationCount} record(s) added`:"Add at least one qualification"}</span></div><div className={documentsComplete?"done":""}><FileText/><strong>Documents</strong><span>{missing.length?`${missing.length} missing`:"Complete"}</span></div><div className={paid?"done":""}><CreditCard/><strong>Application fee</strong><span>{paid?"Paid / not required":fee?cash(fee.amount,fee.currency_code):"Fee rule required"}</span></div><div className={!draft?"done":""}><Send/><strong>Submission</strong><span>{draft?"Draft":"Submitted"}</span></div></div>
  {(paid||!draft)&&<div className="applicant-submission-receipt"><div><strong>{draft?"Payment complete — submit your application":"Application submitted"}</strong><span>Download a PDF copy of the application details you submitted.</span></div><button type="button" className="applicant-secondary" onClick={()=>downloadApplicationReceiptPdf({institution:boot?.institution,applicant,application:app,qualifications,subjectResults})}><Download size={16}/>Download application PDF</button></div>}
  {draft&&!paid&&<div className="applicant-subsection applicant-choice-edit"><div className="applicant-section-title"><div><h4>Programme choices</h4><p>Review and correct programme choices before payment.</p></div>{!editingChoices?<button className="applicant-secondary" onClick={()=>{setChoiceIds(app.choices?.map(c=>c.programme?.id).filter(Boolean)||[]);setEditingChoices(true)}}><Pencil size={15}/>Edit choices</button>:<button className="applicant-secondary" onClick={()=>setEditingChoices(false)}><X size={15}/>Cancel</button>}</div>{editingChoices&&<div className="applicant-choice-editor">{choiceIds.map((id,i)=><label key={i}>Choice {i+1}<select value={id} onChange={e=>{const n=[...choiceIds];n[i]=e.target.value;setChoiceIds(n)}}><option value="">Select programme…</option>{availableProgrammes.map(p=><option key={p.id} value={p.id}>{p.code} — {p.name}</option>)}</select></label>)}{choiceIds.length<(app.cycle?.max_programme_choices||3)&&<button type="button" className="applicant-secondary" onClick={()=>setChoiceIds([...choiceIds,""])}><Plus size={14}/>Add choice</button>}<button type="button" className="applicant-primary" disabled={busy} onClick={saveChoices}>Save programme choices</button></div>}</div>}
  {draft&&<><div className="applicant-subsection"><div className="applicant-section-title"><div><h4>Required documents</h4><p>PDF, JPG, PNG or WebP • Maximum 10 MB per file. Review, replace or remove documents before payment. After payment/submission they are locked for review.</p></div></div>{reqs.map(r=>{const row=(app.documents||[]).find(d=>d.document_type?.toLowerCase()===r.document_type.toLowerCase());const ok=Boolean(row);return <div className="applicant-upload-row applicant-upload-edit-row" key={r.id}><div><strong>{r.display_name}</strong><span>{r.description||r.document_type}{r.is_required?" • Required":""}</span>{row?.file_name&&<small>{row.file_name}</small>}</div>{ok?<div className="applicant-document-edit"><span className="applicant-complete"><CheckCircle2 size={16}/>Uploaded</span><input type="file" accept="application/pdf,image/jpeg,image/png,image/webp" onChange={e=>setFiles({...files,[r.document_type]:e.target.files?.[0]||null})}/><button className="applicant-secondary" disabled={busy||!files[r.document_type]} onClick={()=>replaceDocument(r,row)}><Upload size={15}/>Replace</button><button className="applicant-icon-action danger" disabled={busy} title="Remove document" onClick={()=>removeDocument(row,r.display_name)}><Trash2 size={15}/></button></div>:<><input type="file" accept="application/pdf,image/jpeg,image/png,image/webp" onChange={e=>setFiles({...files,[r.document_type]:e.target.files?.[0]||null})}/><button className="applicant-secondary" disabled={busy||!files[r.document_type]} onClick={()=>upload(r)}><Upload size={15}/>Upload</button></>}</div>;})}{!reqs.length&&<p className="applicant-muted">No compulsory document requirements configured for this route.</p>}
    <div className="applicant-extra-documents">
      <div className="applicant-section-title"><div><h4>Additional supporting documents</h4><p>You may add other documents such as a CV, recommendation letter, portfolio or additional certificate. These do not replace compulsory documents.</p></div></div>
      {(app.documents||[]).filter(d=>String(d.document_type||"").startsWith("Additional - ")).map(d=><div className="applicant-extra-doc-row" key={d.id}><div><strong>{String(d.document_type).replace("Additional - ","")}</strong><span>{d.file_name}</span></div><button type="button" className="applicant-icon-action danger" disabled={busy} title="Remove additional document" onClick={()=>removeDocument(d,String(d.document_type).replace("Additional - ",""))}><Trash2 size={15}/></button></div>)}
      <div className="applicant-extra-doc-add">
        <label>Document name<input value={extraDocLabel} onChange={e=>setExtraDocLabel(e.target.value)} placeholder="e.g. Recommendation letter"/></label>
        <label>Choose file<input type="file" accept="application/pdf,image/jpeg,image/png,image/webp" onChange={e=>setExtraDocFile(e.target.files?.[0]||null)}/></label>
        <button type="button" className="applicant-secondary" disabled={busy||!extraDocLabel.trim()||!extraDocFile} onClick={uploadExtraDocument}><Plus size={15}/>Add document</button>
      </div>
    </div>
   </div>
   <div className="applicant-subsection applicant-payment-row"><div><h4>Application fee</h4><p>{app.cycle?.payment_required?(fee?(prePaymentComplete?`${cash(fee.amount,fee.currency_code)} — requirements complete. You may now pay.`:`${cash(fee.amount,fee.currency_code)} — add a qualification and upload all required documents before payment.`):"No fee rule configured for this route."):"No application fee required."}</p></div>{app.cycle?.payment_required&&!paid&&<button className="applicant-primary" disabled={busy||!fee||!prePaymentComplete} onClick={pay}><CreditCard size={16}/>Pay application fee</button>}</div>
   <div className="applicant-submit-row"><div><strong>Ready to submit?</strong><span>{ready?"All requirements are satisfied. You may submit now.":!hasQualification?"Add at least one qualification first.":!documentsComplete?"Upload all required documents first.":!paid?"Complete and verify application fee payment first.":"Complete the remaining requirements."}</span></div><button className="applicant-primary" disabled={busy||!ready} onClick={submit}><Send size={16}/>Submit application</button></div></>}
  {(app.offers||[]).map(o=><div className={`applicant-offer applicant-offer-${o.response_status||"pending"}`} key={o.id}><div><span className="applicant-eyebrow">Admission Offer</span><h4>{o.programme?.code} — {o.programme?.name}</h4><p>Offer No: {o.offer_number}{o.conditions?` • ${o.conditions}`:""}</p><Pill value={o.response_status}/>{o.response_status==="accepted"&&<p className="applicant-offer-congratulations">Congratulations. You have accepted this admission offer.</p>}</div><div className="applicant-offer-actions"><button className="applicant-secondary" type="button" onClick={()=>downloadAdmissionLetterPdf({institution:boot?.institution,applicant,application:app,offer:o})}><Download size={16}/>Download admission letter</button>{o.response_status==="pending"&&<><button className="applicant-primary" disabled={busy} onClick={()=>respond(o,"accepted")}>Accept offer</button><button className="applicant-danger" disabled={busy} onClick={()=>respond(o,"declined")}>Decline</button></>}</div></div>)}
 </article>;
}
