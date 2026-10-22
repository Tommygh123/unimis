import {useCallback,useEffect,useState} from "react";
import {GraduationCap,Save,Settings2} from "lucide-react";
import Toast from "../../components/Toast";
import {useUserContext} from "../../contexts/UserContext";
import GradingSettings from "./GradingSettings";
import ProgressionSettings from "./ProgressionSettings";
import DegreeClassificationSettings from "./DegreeClassificationSettings";
import "../../styles/modules-078.css";
import "../../styles/settings-080.css";
import {loadStudentLifecycleSettings,saveStudentLifecycleSettings} from "../../services/studentLifecycle";

export default function InstitutionSettings(){
 const {institutionId}=useUserContext();
 const [settings,setSettings]=useState({});
 const [busy,setBusy]=useState(false),[message,setMessage]=useState(""),[error,setError]=useState("");
 const load=useCallback(async()=>{if(!institutionId)return;const r=await loadStudentLifecycleSettings(institutionId);if(r.error)setError(r.error.message);else setSettings(r.data||{});},[institutionId]);
 useEffect(()=>{load();},[load]);
 async function saveLifecycle(){const n=settings.student_numbering||{},fmt=n.format||"{FACULTY}/{DEPARTMENT}/{YY}/{SEQ}";if(!fmt.includes("{SEQ}")||/[{}]/.test(fmt.replace(/\{(PREFIX|FACULTY|DEPARTMENT|PROGRAMME|YY|YYYY|SEQ)\}/g,""))||fmt.length>100||!Number.isInteger(Number(n.digits||3))||Number(n.digits||3)<1||Number(n.digits||3)>12){setError("Use valid format tokens, include {SEQ}, and choose 1–12 sequence digits.");return}setBusy(true);setError("");const r=await saveStudentLifecycleSettings(institutionId,settings);if(r.error)setError(r.error.message);else setMessage("Student lifecycle settings saved.");setBusy(false)}
 const conversion=settings.student_conversion||{},registration=settings.registration||{};
 const patch=(section,key,value)=>setSettings(s=>({...s,[section]:{...(s[section]||{}),[key]:value}}));
 return <section><Toast message={error||message} type={error?"error":"success"} onClose={()=>{setError("");setMessage("")}}/>
 <div className="page-heading"><span className="eyebrow">Institution setup</span><h1>Student Lifecycle Settings</h1><p>Academic years and semesters remain under Academic Management. Configure student conversion, registration and institutional grading here.</p></div>
 <div className="settings-grid">
 <div className="management-card settings-form"><div className="section-title"><div><h2>Student Numbering</h2><p>Choose the institution's own student ID format.</p></div><Settings2/></div>
 <label>Student ID format<input value={settings.student_numbering?.format||"{FACULTY}/{DEPARTMENT}/{YY}/{SEQ}"} onChange={e=>patch("student_numbering","format",e.target.value)}/></label>
 <label>Institution prefix<input value={settings.student_numbering?.prefix||""} onChange={e=>patch("student_numbering","prefix",e.target.value)} placeholder="e.g. JTI"/></label>
 <label>Sequence digits<input type="number" min="1" max="12" value={settings.student_numbering?.digits||3} onChange={e=>patch("student_numbering","digits",Number(e.target.value))}/></label>
 <label>Sequence scope<select value={settings.student_numbering?.scope||"department"} onChange={e=>patch("student_numbering","scope",e.target.value)}><option value="department">Each department</option><option value="programme">Each programme</option><option value="institution">Whole institution</option></select></label>
 <p>Use {'{PREFIX}, {FACULTY}, {DEPARTMENT}, {PROGRAMME}, {YY}, {YYYY}, {SEQ}'}. Include {'{SEQ}'} for a unique sequence. Example: {'{PREFIX}-{YYYY}-{SEQ}'}.</p>
 <div className="number-format-card"><span>PREVIEW (sample academic codes)</span><code>{(settings.student_numbering?.format||"{FACULTY}/{DEPARTMENT}/{YY}/{SEQ}").replaceAll("{PREFIX}",settings.student_numbering?.prefix||"JTI").replaceAll("{FACULTY}","FET").replaceAll("{DEPARTMENT}","ECE").replaceAll("{PROGRAMME}","IT").replaceAll("{YYYY}",String(new Date().getFullYear())).replaceAll("{YY}",String(new Date().getFullYear()).slice(-2)).replaceAll("{SEQ}","1".padStart(Math.min(12,Math.max(1,Number(settings.student_numbering?.digits)||3)),"0"))}</code><p>Changes apply to newly admitted students. Existing student IDs are retained.</p></div>

 </div>
 <div className="management-card settings-form"><div className="section-title"><div><h2>Applicant → Student Conversion</h2><p>Controls what UniMIS creates after an accepted admission offer.</p></div><GraduationCap/></div>
 <label>Initial level<input type="number" step="100" min="100" value={conversion.initial_level||100} onChange={e=>patch("student_conversion","initial_level",Number(e.target.value))}/></label>
 <label className="check-row"><input type="checkbox" checked={conversion.auto_create_period_registration!==false} onChange={e=>patch("student_conversion","auto_create_period_registration",e.target.checked)}/>Create draft semester registration automatically</label>
 <label className="check-row"><input type="checkbox" checked={conversion.auto_assign_student_role!==false} onChange={e=>patch("student_conversion","auto_assign_student_role",e.target.checked)}/>Activate Student Portal role automatically</label>
 <label className="check-row"><input type="checkbox" checked={Boolean(conversion.auto_generate_initial_invoice)} onChange={e=>patch("student_conversion","auto_generate_initial_invoice",e.target.checked)}/>Generate initial invoice automatically when fee structures are ready</label></div>
 <div className="management-card settings-form"><div className="section-title"><div><h2>Registration Policy</h2><p>Controls semester course registration and approval.</p></div></div>
 <div className="form-grid-2"><label>Minimum credits<input type="number" min="0" value={registration.min_credits??0} onChange={e=>patch("registration","min_credits",Number(e.target.value))}/></label><label>Maximum credits<input type="number" min="1" value={registration.max_credits??24} onChange={e=>patch("registration","max_credits",Number(e.target.value))}/></label></div>
 <label className="check-row"><input type="checkbox" checked={Boolean(registration.require_fee_clearance)} onChange={e=>patch("registration","require_fee_clearance",e.target.checked)}/>Require fee clearance before registration</label>
 {registration.require_fee_clearance&&<label>Minimum fee percentage<input type="number" min="0" max="100" value={registration.minimum_fee_percentage??0} onChange={e=>patch("registration","minimum_fee_percentage",Number(e.target.value))}/></label>}
 <label className="check-row"><input type="checkbox" checked={registration.require_adviser_approval!==false} onChange={e=>patch("registration","require_adviser_approval",e.target.checked)}/>Require registrar/adviser approval after student submission</label>
 <label className="check-row"><input type="checkbox" checked={registration.auto_select_required_courses!==false} onChange={e=>patch("registration","auto_select_required_courses",e.target.checked)}/>Automatically include required/core courses</label>
 <label className="check-row"><input type="checkbox" checked={Boolean(registration.allow_late_registration)} onChange={e=>patch("registration","allow_late_registration",e.target.checked)}/>Allow late registration</label></div></div>
 <ProgressionSettings/>
 <GradingSettings/>
 <DegreeClassificationSettings/>
 <div className="settings-savebar"><div><strong>Academic calendar is managed under Academic Management</strong><span>Use Academic Years and Semesters there to set the current year and semester.</span></div><button className="primary-button" onClick={saveLifecycle} disabled={busy}><Save size={16}/>{busy?"Saving…":"Save Student Lifecycle Settings"}</button></div>
 </section>
}