import "../../styles/modules-078.css";
import {useEffect,useRef,useState} from "react";
import {Link,useLocation,useNavigate} from "react-router-dom";
import {supabase} from "../../lib/supabase";
import "../../styles/academic-workspaces-115.css";
import toast from "react-hot-toast";
import {useConfirm} from "../../contexts/ConfirmContext";
import "../../styles/analytics-052b.css";
import "../../styles/portal-professional-058.css";
import "../../styles/portal-professional-058b.css";

import {BookOpen,CalendarDays,Clock3,MapPin,RefreshCw,UsersRound,ChevronLeft,ClipboardCheck,Save} from "lucide-react";

import {lecturerResultPreview,submitCourseResults,lecturerResultAnalytics} from "../../services/results";

import {loadLecturerWorkspace,loadLecturerClassList,loadAttendanceSessions,createAttendanceSession,loadAttendanceRegister,saveAttendance,loadLecturerAssessments,createLecturerAssessment,loadAssessmentMarksheet,saveAssessmentScores,configureResultEntryMode,loadCaExamMarksheet,saveCaExamScores} from "../../services/lecturerPortal";

const days={0:"Sunday",1:"Monday",2:"Tuesday",3:"Wednesday",4:"Thursday",5:"Friday",6:"Saturday",7:"Sunday"};

const fmt=t=>t?String(t).slice(0,5):"";

const today=()=>new Date().toISOString().slice(0,10);


function PerformanceLineChart({trend=[]}){
  if(!trend.length)return <div className="analytics-empty">No historical result period is available yet.</div>;
  if(trend.length===1)return <div className="trend-baseline"><div className="baseline-score">{trend[0].average}%</div><strong>Baseline established</strong><span>{trend[0].period} • {trend[0].students} students • {trend[0].pass_rate}% pass rate</span><p>A second academic period is required before UniMIS can calculate and display a true performance trend.</p></div>;
  const w=760,h=230,p=36;
  const vals=trend.map(x=>Number(x.average||0));
  const x=i=>trend.length===1?w/2:p+(i*(w-2*p)/(trend.length-1));
  const y=v=>h-p-(Math.max(0,Math.min(100,v))*(h-2*p)/100);
  const points=vals.map((v,i)=>`${x(i)},${y(v)}`).join(" ");
  return <div className="analytics-chart-wrap"><svg className="analytics-line-chart" viewBox={`0 0 ${w} ${h}`} role="img" aria-label="Average score trend">
    {[0,25,50,75,100].map(v=><g key={v}><line x1={p} x2={w-p} y1={y(v)} y2={y(v)} className="chart-grid"/><text x={8} y={y(v)+4} className="chart-axis">{v}%</text></g>)}
    <polyline points={points} className="chart-line"/>
    {vals.map((v,i)=><g key={i}><circle cx={x(i)} cy={y(v)} r="5" className="chart-point"/><text x={x(i)} y={y(v)-10} textAnchor="middle" className="chart-value">{v}%</text><text x={x(i)} y={h-9} textAnchor="middle" className="chart-label">{String(trend[i].period||"").slice(0,14)}</text></g>)}
  </svg></div>
}

function GradeBars({grades=[]}){
  if(!grades.length)return <div className="analytics-empty">Grade distribution becomes available as course results are calculated.</div>;
  const max=Math.max(1,...grades.map(x=>Number(x.count||0)));
  return <div className="grade-bars">{grades.map((g,i)=><div className="grade-bar-item" key={`${g.grade}-${i}`}><div className="grade-bar-head"><strong>{g.grade}</strong><span>{g.count} student{Number(g.count)===1?"":"s"}</span></div><div className="grade-bar-track"><div className="grade-bar-fill" style={{width:`${Number(g.count||0)*100/max}%`}}/></div></div>)}</div>
}

export default function LecturerDashboard(){
 const [corrections133,setCorrections133]=useState([]);

 const location=useLocation(),navigate=useNavigate();
 const courseRequest=useRef(0);
 const [courseFilters,setCourseFilters]=useState({scope:"all",year:"",period:"",query:""}),[classSearch,setClassSearch]=useState("");
 const portalView=location.pathname.split("/")[2]||"dashboard";

 const confirmAction=useConfirm();

 const [data,setData]=useState(null),[error,setError]=useState(""),[busy,setBusy]=useState(false),[course,setCourse]=useState(null);

 const previousPortalView=useRef(portalView);
 useEffect(()=>{if(previousPortalView.current!==portalView){setCourse(null);setClassData(null);setSession(null);setAssessment(null);setResultPreview(null);setAnalytics(null);previousPortalView.current=portalView}},[portalView]);

 const [classData,setClassData]=useState(null),[sessions,setSessions]=useState([]),[session,setSession]=useState(null),[register,setRegister]=useState([]);

 const [form,setForm]=useState({session_date:today(),start_time:"08:00",end_time:"10:00",topic:"",venue:""});

 const [assessments,setAssessments]=useState([]),[assessment,setAssessment]=useState(null),[marks,setMarks]=useState([]);

 const [resultPreview,setResultPreview]=useState(null);
  const [caWeight,setCaWeight]=useState(40),[examWeight,setExamWeight]=useState(60),[caExam,setCaExam]=useState(null),[analytics,setAnalytics]=useState(null);

 const [af,setAf]=useState({name:"",assessment_type:"assignment",max_score:"100",weight_percent:"10",due_date:""});

 async function refreshResults(id=course?.course_offering_id){if(!id)return;const correction=await supabase.rpc('unimis_lecturer_corrections133',{p_offering:id});setCorrections133(correction.data||[]);const [r,a]=await Promise.all([lecturerResultPreview(id),lecturerResultAnalytics(id)]);if(r.error)setError(r.error.message);else setResultPreview(r.data);if(!a.error)setAnalytics(a.data)}
 useEffect(()=>{let active=true;setCorrections133([]);if(course?.course_offering_id)supabase.rpc('unimis_lecturer_corrections133',{p_offering:course.course_offering_id}).then(r=>{if(active)setCorrections133(r.data||[])});return()=>{active=false}},[course?.course_offering_id]);
  const resultLocked130=id=>['submitted','approved','published'].includes((resultPreview?.students||[]).find(r=>r.course_registration_id===id)?.result_status);
  async function openCaExam130(){setBusy(true);setError('');const m=await loadCaExamMarksheet(course.course_offering_id);if(m.error)setError(m.error.message);else setCaExam({...m.data,students:(m.data?.students||[]).map(x=>({...x,ca_score:x.ca_score??'',exam_score:x.exam_score??''}))});setBusy(false)}
  async function useCaExam(){setBusy(true);setError("");const r=await configureResultEntryMode(course.course_offering_id,"ca_exam",caWeight,examWeight);if(r.error)setError(r.error.message);else{const m=await loadCaExamMarksheet(course.course_offering_id);if(m.error)setError(m.error.message);else setCaExam({...m.data,students:(m.data?.students||[]).map(x=>({...x,ca_score:x.ca_score??"",exam_score:x.exam_score??""}))});toast.success("CA + Exam result entry enabled.");await refreshAssessments();await refreshResults()}setBusy(false)}
  async function saveCaExam(){setBusy(true);setError("");const r=await saveCaExamScores(course.course_offering_id,(caExam?.students||[]).filter(x=>!resultLocked130(x.course_registration_id)).map(x=>({student_id:x.student_id,course_registration_id:x.course_registration_id,student_number:x.student_number,ca_score:x.ca_score,exam_score:x.exam_score})));if(r.error)setError(r.error.message);else{toast.success(`CA and Exam scores saved for ${r.data?.saved||0} students.`);const m=await loadCaExamMarksheet(course.course_offering_id);if(!m.error)setCaExam({...m.data,students:(m.data?.students||[]).map(x=>({...x,ca_score:x.ca_score??"",exam_score:x.exam_score??""}))});await refreshResults()}setBusy(false)}
  function exportCaExam(){const rows=[["Student Number","Student Name","Continuous Assessment","Examination"],...(caExam?.students||[]).map(x=>[x.student_number,x.student_name,x.ca_score??"",x.exam_score??""])];const csv=rows.map(r=>r.map(v=>`"${String(v??"").replaceAll('"','""')}"`).join(",")).join("\r\n");const a=document.createElement("a");a.href=URL.createObjectURL(new Blob([csv],{type:"text/csv;charset=utf-8"}));a.download=`${course.course_code}_CA_Exam.csv`;a.click();URL.revokeObjectURL(a.href)}
  function importCaExam(file){const reader=new FileReader();reader.onload=()=>{const lines=String(reader.result).split(/\r?\n/).filter(Boolean);const rows=lines.slice(1).map(line=>{const q=[];let cur="",inside=false;for(let i=0;i<line.length;i++){const ch=line[i];if(ch==='"'){if(inside&&line[i+1]==='"'){cur+='"';i++}else inside=!inside}else if(ch===","&&!inside){q.push(cur);cur=""}else cur+=ch}q.push(cur);return q});const byNo=new Map(rows.map(r=>[String(r[0]).trim(),r]));setCaExam(x=>({...x,students:(x?.students||[]).map(s=>{const r=byNo.get(String(s.student_number).trim());return r&&!resultLocked130(s.course_registration_id)?{...s,ca_score:r[2]??"",exam_score:r[3]??""}:s})}))};reader.readAsText(file)}

 async function submitResults(){const ok=await confirmAction({title:"Submit course results?",message:"Submit this course result sheet for approval? Marks will be locked until an administrator returns it.",confirmLabel:"Submit Results"});if(!ok)return;setBusy(true);setError("");const r=await submitCourseResults(course.course_offering_id);if(r.error)setError(r.error.message);else{toast.success(`${r.data?.submitted||0} results submitted for approval.`);await refreshResults()}setBusy(false)}

 async function refreshAssessments(id=course?.course_offering_id){if(!id)return;const r=await loadLecturerAssessments(id);r.error?setError(r.error.message):setAssessments(r.data||[])}

 async function addAssessment(e){e.preventDefault();setBusy(true);setError("");const r=await createLecturerAssessment(course.course_offering_id,af);if(r.error)setError(r.error.message);else{setAf({name:"",assessment_type:"assignment",max_score:"100",weight_percent:"10",due_date:""});await refreshAssessments()}setBusy(false)}

 async function openMarksheet(a){setBusy(true);setError("");setAssessment(a);const r=await loadAssessmentMarksheet(a.id);if(r.error)setError(r.error.message);else setMarks((r.data?.students||[]).map(x=>({...x,raw_score:x.raw_score??"",remarks:x.remarks||""})));setBusy(false)}

 async function saveMarks(){setBusy(true);setError("");const r=await saveAssessmentScores(assessment.id,marks.filter(x=>!resultLocked130(x.course_registration_id)).map(x=>({student_id:x.student_id,course_registration_id:x.course_registration_id,student_number:x.student_number,raw_score:x.raw_score,remarks:x.remarks||null})));if(r.error)setError(r.error.message);else{toast.success(`Marks saved for ${r.data?.saved??0} students.`);await refreshResults()}setBusy(false)}

 function exportMarks(){const rows=[["Student Number","Student Name","Score","Remarks"],...marks.map(x=>[x.student_number,[x.first_name,x.middle_name,x.last_name].filter(Boolean).join(" "),x.raw_score??"",x.remarks||""])];const csv=rows.map(r=>r.map(v=>`"${String(v??"").replaceAll('"','""')}"`).join(",")).join("\r\n");const a=document.createElement("a");a.href=URL.createObjectURL(new Blob([csv],{type:"text/csv;charset=utf-8"}));a.download=`${course.course_code}_${assessment.name}_marks.csv`;a.click();URL.revokeObjectURL(a.href)}

 function importMarks(file){const reader=new FileReader();reader.onload=()=>{const lines=String(reader.result).split(/\r?\n/).filter(Boolean);const parsed=lines.slice(1).map(line=>{const q=[];let cur="",inside=false;for(let i=0;i<line.length;i++){const ch=line[i];if(ch==='"'){if(inside&&line[i+1]==='"'){cur+='"';i++}else inside=!inside}else if(ch===","&&!inside){q.push(cur);cur=""}else cur+=ch}q.push(cur);return q});const byNo=new Map(parsed.map(r=>[String(r[0]).trim(),r]));setMarks(x=>x.map(m=>{const r=byNo.get(String(m.student_number).trim());return r&&!resultLocked130(m.course_registration_id)?{...m,raw_score:r[2]??"",remarks:r[3]??""}:m}))};reader.readAsText(file)}



 async function load(){setBusy(true);setError("");const r=await loadLecturerWorkspace();r.error?setError(r.error.message):setData(r.data);setBusy(false)}

 useEffect(()=>{load()},[]);

  async function loadCourse(c){const token=++courseRequest.current;setBusy(true);setError("");setCourse(c);setSession(null);setClassData(null);setClassSearch("");setAssessment(null);setMarks([]);setCaExam(null);setAssessments([]);setResultPreview(null);setAnalytics(null);setSessions([]);setRegister([]);try{const classResponse=await loadLecturerClassList(c.course_offering_id);if(courseRequest.current!==token)return;if(classResponse.error)throw classResponse.error;const rows=classResponse.data?.students||[];const withPhotos=await Promise.all(rows.map(async r=>{if(r.photo_url||!r.applicant_photo_path)return r;const photo=await supabase.storage.from("admission-documents").createSignedUrl(r.applicant_photo_path,3600);return {...r,photo_url:photo.data?.signedUrl}}));if(courseRequest.current!==token)return;setClassData({...classResponse.data,students:withPhotos});if(portalView==="attendance"){const sessionsResponse=await loadAttendanceSessions(c.course_offering_id);if(courseRequest.current!==token)return;if(sessionsResponse.error)throw sessionsResponse.error;setSessions(sessionsResponse.data||[])}if(portalView==="results"){const [assessmentsResponse,previewResponse,analyticsResponse]=await Promise.all([loadLecturerAssessments(c.course_offering_id),lecturerResultPreview(c.course_offering_id),lecturerResultAnalytics(c.course_offering_id)]);if(courseRequest.current!==token)return;if(assessmentsResponse.error||previewResponse.error)throw assessmentsResponse.error||previewResponse.error;setAssessments(assessmentsResponse.data||[]);setResultPreview(previewResponse.data);setAnalytics(analyticsResponse.data)}}catch(e){if(courseRequest.current===token)setError(e.message)}finally{if(courseRequest.current===token)setBusy(false)}}
 function openClass(c){navigate(`/lecturer/${["classes","attendance","results"].includes(portalView)?portalView:"classes"}?course=${c.course_offering_id}`)}
 const requestedCourse=new URLSearchParams(location.search).get("course");
 useEffect(()=>{if(!requestedCourse||!data||!["classes","attendance","results"].includes(portalView)){setCourse(null);return}const c=(data.courses||[]).find(x=>x.course_offering_id===requestedCourse);if(c)loadCourse(c);else{setCourse(null);setError("This course offering is not allocated to your lecturer account.")}return()=>{courseRequest.current++}},[requestedCourse,portalView,data]);


 async function addSession(e){e.preventDefault();setBusy(true);setError("");const r=await createAttendanceSession(course.course_offering_id,form);if(r.error)setError(r.error.message);else{const s=await loadAttendanceSessions(course.course_offering_id);setSessions(s.data||[]);}setBusy(false)}

 async function take(s){setBusy(true);setError("");setSession(s);const r=await loadAttendanceRegister(s.id);if(r.error)setError(r.error.message);else setRegister((r.data||[]).map(x=>({...x,status:x.attendance_status||"present",remarks:x.remarks||""})));setBusy(false)}

 function markAll(status){setRegister(x=>x.map(r=>({...r,status})))}

 async function save(){setBusy(true);setError("");const r=await saveAttendance(session.id,register.map(x=>({student_id:x.student_id,course_registration_id:x.course_registration_id,status:x.status,remarks:x.remarks||null})));if(r.error)setError(r.error.message);else toast.success(`Attendance saved for ${r.data?.saved??register.length} students.`);setBusy(false)}

 const allCourses=data?.courses||[],courses=allCourses.filter(c=>(courseFilters.scope==="all"||(courseFilters.scope==="current"?c.is_current:["closed","archived"].includes(c.period_status)))&&(!courseFilters.year||c.academic_year_id===courseFilters.year)&&(!courseFilters.period||c.academic_period_id===courseFilters.period)&&[c.course_code,c.course_name,c.programme_code].join(" ").toLowerCase().includes(courseFilters.query.toLowerCase())),schedule=(data?.schedule||[]).filter(x=>courses.some(c=>c.course_offering_id===x.course_offering_id)),l=data?.lecturer||{};
 const classRows=(classData?.students||[]).filter(s=>[s.student_number,s.first_name,s.middle_name,s.last_name,s.email].join(" ").toLowerCase().includes(classSearch.toLowerCase()));

 if(course) return <div className="lecturer-workspace portal-058"><button className="secondary-action back-action" onClick={()=>navigate(`/lecturer/${portalView}`)}><ChevronLeft size={16}/>Back to {portalView==="classes"?"Class Lists":portalView==="attendance"?"Attendance":"Results"}</button><div className="management-header lecturer-hero portal-hero"><div><span className="section-kicker">{portalView==="classes"?"CLASS LIST":portalView==="attendance"?"ATTENDANCE":"RESULTS WORKSPACE"}</span><h1>{course.course_code} — {course.course_name}</h1><p>{course.programme_code||""} • Section {course.section_code||"A"} • Level {course.level_number||"—"} • {course.academic_period}</p></div></div>{error&&<div className="form-error">{error}</div>}{portalView==="classes"&&<><section className="management-card"><div className="section-title"><div><h2>Class List</h2><p>Approved students registered for this course offering.</p></div><span className="count-badge">{classData?.count||0} students</span></div>

   <div className="academic115"><label>Find a student<input placeholder="Student ID, name or email" value={classSearch} onChange={e=>setClassSearch(e.target.value)}/></label><p>{classRows.length} matching students</p></div><div className="responsive-table"><table><thead><tr><th>#</th><th>Student Number</th><th>Student</th><th>Email</th><th>Registration</th></tr></thead><tbody>{classRows.map((s,i)=><tr key={s.student_id}><td>{i+1}</td><td><strong>{s.student_number}</strong></td><td><div className="academic115-person">{s.photo_url?<img className="academic115-photo" src={s.photo_url} alt={`${s.first_name} ${s.last_name}`}/>:<span className="academic115-photo">{s.first_name?.[0]}{s.last_name?.[0]}</span>}{[s.first_name,s.middle_name,s.last_name].filter(Boolean).join(" ")}</div></td><td>{s.email||"—"}</td><td><span className="status-pill verified">{s.registration_status}</span></td></tr>)}{!busy&&!classRows.length&&<tr><td colSpan="5" className="table-empty">No approved registered students for this offering.</td></tr>}</tbody></table></div>

  </section>

  </>}{portalView==="results"&&<><section className="management-card">
    <div className="section-title"><div><h2>Result Entry Method</h2><p>Choose detailed semester assessments, or enter only consolidated Continuous Assessment and Final Examination marks after scripts are marked.</p></div></div>
    <div className="assessment-form">
      <label>CA weight %<input type="number" min="1" max="99" value={caWeight} onChange={e=>{const n=Number(e.target.value);setCaWeight(n);setExamWeight(100-n)}}/></label>
      <label>Exam weight %<input type="number" min="1" max="99" value={examWeight} onChange={e=>{const n=Number(e.target.value);setExamWeight(n);setCaWeight(100-n)}}/></label>
      <button className="primary-action" disabled={busy||caWeight+examWeight!==100} onClick={useCaExam}>Use CA + Exam Mode</button><button className="secondary-action" disabled={busy} onClick={openCaExam130}>Open Existing CA + Exam Sheet</button>
    </div>
    {caExam&&<>
      <div className="section-title"><div><h3>Continuous Assessment + Examination</h3><p>Enter the two final marks directly, or download the sheet, complete it in Excel and upload the CSV.</p></div><div className="table-actions"><button className="secondary-action" onClick={exportCaExam}>Download CSV</button><label className="secondary-action upload-action">Upload CSV<input type="file" accept=".csv,text/csv" hidden onChange={e=>e.target.files?.[0]&&importCaExam(e.target.files[0])}/></label><button className="primary-action" onClick={saveCaExam} disabled={busy}><Save size={16}/>Save CA + Exam</button></div></div>
      <div className="responsive-table"><table><thead><tr><th>Student</th><th>Number</th><th>CA / {caExam.ca_max}</th><th>Exam / {caExam.exam_max}</th><th>Total / 100</th></tr></thead><tbody>{(caExam.students||[]).map((s,i)=><tr key={s.student_id}><td><strong>{s.student_name}</strong></td><td>{s.student_number}</td><td><input type="number" min="0" max={caExam.ca_max} step="0.01" value={s.ca_score} disabled={resultLocked130(s.course_registration_id)} onChange={e=>setCaExam(x=>({...x,students:x.students.map((a,j)=>j===i?{...a,ca_score:e.target.value}:a)}))}/></td><td><input type="number" min="0" max={caExam.exam_max} step="0.01" value={s.exam_score} disabled={resultLocked130(s.course_registration_id)} onChange={e=>setCaExam(x=>({...x,students:x.students.map((a,j)=>j===i?{...a,exam_score:e.target.value}:a)}))}/></td><td>{(Number(s.ca_score||0)+Number(s.exam_score||0)).toFixed(2)}</td></tr>)}</tbody></table></div>
    </>}
  </section>

  <section className="management-card"><div className="section-title"><div><h2>Detailed Assessments & Marks</h2><p>Create assessments and enter or import marks for this registered class.</p></div><span className="count-badge">{assessments.reduce((n,a)=>n+Number(a.weight_percent||0),0)}% allocated</span></div>

   <form className="assessment-form" onSubmit={addAssessment}><label>Name<input value={af.name} onChange={e=>setAf({...af,name:e.target.value})} placeholder="Assignment 1" required/></label><label>Type<select value={af.assessment_type} onChange={e=>setAf({...af,assessment_type:e.target.value})}><option value="quiz">Quiz</option><option value="assignment">Assignment</option><option value="midsem">Mid-Sem</option><option value="project">Project</option><option value="practical">Practical</option><option value="presentation">Presentation</option><option value="final_exam">Final Exam</option><option value="other">Other</option></select></label><label>Max score<input type="number" min="1" step="0.01" value={af.max_score} onChange={e=>setAf({...af,max_score:e.target.value})} required/></label><label>Weight %<input type="number" min="0.01" max="100" step="0.01" value={af.weight_percent} onChange={e=>setAf({...af,weight_percent:e.target.value})} required/></label><label>Due date<input type="date" value={af.due_date} onChange={e=>setAf({...af,due_date:e.target.value})}/></label><button className="primary-action" disabled={busy}>Create Assessment</button></form>

   <div className="responsive-table"><table><thead><tr><th>Assessment</th><th>Type</th><th>Maximum</th><th>Weight</th><th>Status</th><th>Marks</th></tr></thead><tbody>{assessments.map(a=><tr key={a.id}><td><strong>{a.name}</strong></td><td>{a.assessment_type.replaceAll("_"," ")}</td><td>{a.max_score}</td><td>{a.weight_percent}%</td><td>{a.status}</td><td><button className="table-action" onClick={()=>openMarksheet(a)}>Enter Marks</button></td></tr>)}{!assessments.length&&<tr><td colSpan="6" className="table-empty">No assessments created for this course.</td></tr>}</tbody></table></div>

  </section>

  {assessment&&<section className="management-card marksheet"><div className="section-title"><div><h2>{assessment.name} — Marksheet</h2><p>Maximum {assessment.max_score} • Weight {assessment.weight_percent}%</p></div><div className="table-actions"><button className="secondary-action" onClick={exportMarks}>Download Excel/CSV</button><label className="secondary-action upload-action">Upload Excel/CSV<input type="file" accept=".csv,text/csv" hidden onChange={e=>e.target.files?.[0]&&importMarks(e.target.files[0])}/></label><button className="primary-action" onClick={saveMarks} disabled={busy}><Save size={16}/>Save Marks</button></div></div>

   <div className="upload-note">The downloaded CSV opens in Excel. Keep Student Number unchanged, enter Score and Remarks, save as CSV, then upload it.</div>

   <div className="responsive-table"><table><thead><tr><th>Student</th><th>Number</th><th>Score / {assessment.max_score}</th><th>Weighted</th><th>Remarks</th></tr></thead><tbody>{marks.map((m,i)=>{const w=m.raw_score===""?"—":((Number(m.raw_score)/Number(assessment.max_score))*Number(assessment.weight_percent)).toFixed(2);return <tr key={m.student_id}><td>{[m.first_name,m.middle_name,m.last_name].filter(Boolean).join(" ")}</td><td><strong>{m.student_number}</strong></td><td><input type="number" min="0" max={assessment.max_score} step="0.01" value={m.raw_score} disabled={resultLocked130(m.course_registration_id)} onChange={e=>setMarks(x=>x.map((a,j)=>j===i?{...a,raw_score:e.target.value}:a))}/></td><td>{w}%</td><td><input value={m.remarks||""} disabled={resultLocked130(m.course_registration_id)} onChange={e=>setMarks(x=>x.map((a,j)=>j===i?{...a,remarks:e.target.value}:a))}/></td></tr>})}</tbody></table></div>

  </section>}

  <section className="management-card result-preview"><div className="section-title"><div><h2>Course Results</h2><p>Automatic totals and grades from saved assessment marks.</p></div><div className="table-actions"><span className="count-badge">{resultPreview?.assessment_weight??0}% assessment weight</span><button className="primary-action" disabled={busy||!resultPreview?.ready||(resultPreview?.students||[]).filter(x=>!resultLocked130(x.course_registration_id)).some(x=>Number(x.missing_assessments)>0)||(resultPreview?.students||[]).every(x=>resultLocked130(x.course_registration_id))} onClick={submitResults}>Submit Draft / Returned Results</button></div></div>

   {!resultPreview?.ready&&<div className="upload-note">Results cannot be submitted until active assessment weights total exactly 100%.</div>}

   {corrections133.length>0&&<section className="notice-panel"><h3>Returned Results / Review Notes</h3>{corrections133.map((r,i)=><p key={i}><strong>{r.student_number} · {r.student}</strong> · {r.status} · {new Date(r.date).toLocaleString()}<br/>{r.note}</p>)}</section>}<div className="responsive-table"><table><thead><tr><th>Student</th><th>Number</th><th>Total</th><th>Grade</th><th>GP</th><th>Missing</th><th>Status</th></tr></thead><tbody>{(resultPreview?.students||[]).map(r=><tr key={r.course_registration_id}><td><strong>{r.student_name}</strong></td><td>{r.student_number}</td><td>{r.total_score}%</td><td>{r.letter_grade||"—"}</td><td>{r.grade_point??"—"}</td><td>{r.missing_assessments||0}</td><td><span className={`status-pill ${r.result_status==="published"?"verified":""}`}>{r.result_status||"draft"}</span></td></tr>)}{!resultPreview?.students?.length&&<tr><td colSpan="7" className="table-empty">Save assessment marks to build the course result sheet.</td></tr>}</tbody></table></div>

  </section>

  <section className="management-card analytics-panel">
    <div className="section-title"><div><span className="section-kicker">PERFORMANCE INSIGHT</span><h2>Results Analytics</h2><p>Visual class performance, grade distribution and historical trends for this course.</p></div></div>
    {analytics&&<>
      <div className="analytics-kpi-grid">
        <div className="analytics-kpi analytics-kpi-blue"><span>Class Average</span><strong>{analytics.average??0}%</strong><small>{Number(analytics.average)>=70?"Strong class average":Number(analytics.average)>=50?"Moderate class average":"Low class average"}</small></div>
        <div className="analytics-kpi analytics-kpi-green"><span>Pass Rate</span><strong>{analytics.pass_rate??0}%</strong><small>{analytics.pass_count??0} passed • {analytics.fail_count??0} failed</small></div>
        <div className="analytics-kpi analytics-kpi-purple"><span>Highest Score</span><strong>{analytics.highest??0}%</strong><small>Best class performance</small></div>
        <div className="analytics-kpi analytics-kpi-amber"><span>Lowest Score</span><strong>{analytics.lowest??0}%</strong><small>Student support indicator</small></div>
      </div>

      <div className="analytics-visual-grid">
        <div className="analytics-card">
          <div className="analytics-card-head"><div><h3>Performance Trend</h3><p>Average score across academic periods</p></div><span className="analytics-chip">Average %</span></div>
          <PerformanceLineChart trend={analytics.trend||[]}/>
        </div>
        <div className="analytics-card">
          <div className="analytics-card-head"><div><h3>Grade Distribution</h3><p>Number of students in each grade band</p></div></div>
          <GradeBars grades={analytics.grade_distribution||[]}/>
        </div>
      </div>

      <div className="analytics-visual-grid analytics-bottom-grid">
        <div className="analytics-card">
          <div className="analytics-card-head"><div><h3>CA vs Examination</h3><p>Compare coursework and final examination performance</p></div></div>
          {analytics.ca_average!=null&&analytics.exam_average!=null?
          <div className="compare-bars">
            <div><div className="compare-label"><span>Continuous Assessment</span><strong>{analytics.ca_average}</strong></div><div className="compare-track"><div className="compare-fill ca-fill" style={{width:`${Math.min(100,Number(analytics.ca_average)/(Number(caWeight)||40)*100)}%`}}/></div></div>
            <div><div className="compare-label"><span>Final Examination</span><strong>{analytics.exam_average}</strong></div><div className="compare-track"><div className="compare-fill exam-fill" style={{width:`${Math.min(100,Number(analytics.exam_average)/(Number(examWeight)||60)*100)}%`}}/></div></div>
          </div>:<div className="analytics-empty">CA vs Examination comparison is available when CA + Exam marks have been entered.</div>}
        </div>
        <div className="analytics-card analytics-insight">
          <div className="analytics-card-head"><div><h3>Performance Interpretation</h3><p>Automatic indicators for lecturer review</p></div></div>
          <div className={`performance-banner ${Number(analytics.pass_rate)>=80?"good":Number(analytics.pass_rate)>=60?"fair":"attention"}`}>
            <strong>{Number(analytics.pass_rate)>=80?"Good overall performance":Number(analytics.pass_rate)>=60?"Satisfactory with areas to review":"Performance requires attention"}</strong>
            <span>{Number(analytics.pass_rate)>=80?"Most registered students are meeting the pass standard.":Number(analytics.pass_rate)>=60?"Review weaker students and difficult assessment areas.":"Review assessment difficulty, teaching coverage and students needing academic support."}</span>
          </div>
          {analytics.ca_average!=null&&analytics.exam_average!=null&&Math.abs(Number(analytics.ca_average)-Number(analytics.exam_average))>=10&&<div className="analytics-alert">CA and examination averages show a notable gap. This should be reviewed during moderation.</div>}
        </div>
      </div>
    </>}
  </section>

  </>}{portalView==="attendance"&&<><section className="management-card"><div className="section-title"><div><h2>Attendance Sessions</h2><p>Create a teaching session, then mark attendance from the approved class list.</p></div></div>

   <form className="attendance-session-form" onSubmit={addSession}><label>Date<input type="date" value={form.session_date} onChange={e=>setForm({...form,session_date:e.target.value})} required/></label><label>Start<input type="time" value={form.start_time} onChange={e=>setForm({...form,start_time:e.target.value})} required/></label><label>End<input type="time" value={form.end_time} onChange={e=>setForm({...form,end_time:e.target.value})} required/></label><label>Venue<input value={form.venue} onChange={e=>setForm({...form,venue:e.target.value})} placeholder="e.g. Lab 1"/></label><label className="topic-field">Topic<input value={form.topic} onChange={e=>setForm({...form,topic:e.target.value})} placeholder="Teaching topic"/></label><button className="primary-action" disabled={busy}><ClipboardCheck size={16}/>Create Session</button></form>

   <div className="responsive-table"><table><thead><tr><th>Date</th><th>Time</th><th>Topic</th><th>Venue</th><th>Status</th><th>Action</th></tr></thead><tbody>{sessions.map(s=><tr key={s.id}><td>{s.session_date}</td><td>{fmt(s.start_time)}–{fmt(s.end_time)}</td><td>{s.topic||"—"}</td><td>{s.venue||"—"}</td><td>{s.attendance_open?"Open":s.status||"—"}</td><td><button className="table-action" onClick={()=>take(s)}>Take attendance</button></td></tr>)}{!sessions.length&&<tr><td colSpan="6" className="table-empty">No attendance sessions yet.</td></tr>}</tbody></table></div>

  </section>

  {session&&<section className="management-card attendance-register"><div className="section-title"><div><h2>Attendance Register</h2><p>{session.session_date} • {fmt(session.start_time)}–{fmt(session.end_time)} • {session.topic||course.course_name}</p></div><div className="table-actions"><button className="secondary-action" onClick={()=>markAll("present")}>Mark all Present</button><button className="primary-action" onClick={save} disabled={busy}><Save size={16}/>Save Attendance</button></div></div>

   <div className="responsive-table"><table><thead><tr><th>Student</th><th>Number</th><th>Status</th><th>Remarks</th></tr></thead><tbody>{register.map((r,i)=><tr key={r.student_id}><td><strong>{[r.first_name,r.middle_name,r.last_name].filter(Boolean).join(" ")}</strong></td><td>{r.student_number}</td><td><select value={r.status} onChange={e=>setRegister(x=>x.map((a,j)=>j===i?{...a,status:e.target.value}:a))}><option value="present">Present</option><option value="absent">Absent</option><option value="late">Late</option><option value="excused">Excused</option></select></td><td><input value={r.remarks||""} onChange={e=>setRegister(x=>x.map((a,j)=>j===i?{...a,remarks:e.target.value}:a))} placeholder="Optional"/></td></tr>)}</tbody></table></div>

  </section>}
</>}</div>;

 return <div className="lecturer-workspace portal-058">
  <div className="management-header lecturer-hero portal-hero"><div><span className="section-kicker">LECTURER PORTAL</span><h1>{({dashboard:"Dashboard",courses:"My Courses",timetable:"My Timetable",classes:"Class List",attendance:"Attendance",results:"Results"}[portalView]||"Dashboard")}</h1><p>{portalView==="dashboard"?(l.first_name?`Welcome, ${l.first_name}. ${[l.academic_rank,l.specialization].filter(Boolean).join(" • ")}`:"My Teaching Workspace"):"Teaching and academic management workspace."}</p></div><button className="secondary-action" onClick={load}><RefreshCw size={16}/>Refresh</button></div>
  {error&&<div className="form-error">{error}</div>}
  <section className="academic115 academic115-card"><div className="academic115-filters"><label>Teaching history<select value={courseFilters.scope} onChange={e=>setCourseFilters({...courseFilters,scope:e.target.value})}><option value="all">All assigned periods</option><option value="current">Current period</option><option value="previous">Previous: closed / archived</option></select></label><label>Academic year<select value={courseFilters.year} onChange={e=>setCourseFilters({...courseFilters,year:e.target.value,period:""})}><option value="">All years</option>{[...new Map(allCourses.map(c=>[c.academic_year_id,c])).values()].map(c=><option key={c.academic_year_id} value={c.academic_year_id}>{c.academic_year}</option>)}</select></label><label>Semester / period<select value={courseFilters.period} onChange={e=>setCourseFilters({...courseFilters,period:e.target.value})}><option value="">All periods</option>{[...new Map(allCourses.filter(c=>!courseFilters.year||c.academic_year_id===courseFilters.year).map(c=>[c.academic_period_id,c])).values()].map(c=><option key={c.academic_period_id} value={c.academic_period_id}>{c.academic_period}</option>)}</select></label><label>Search courses<input value={courseFilters.query} placeholder="Course or programme" onChange={e=>setCourseFilters({...courseFilters,query:e.target.value})}/></label></div><div className="academic115-toolbar"><span>{courses.length} matching assigned offerings</span><Link className="primary-action" to="/lecturer/reports">Reports & Teaching History</Link></div></section>
  {portalView==="dashboard"&&<><div className="lecturer-stat-grid portal-kpis"><div className="lecturer-stat"><BookOpen/><div><strong>{courses.length}</strong><span>Assigned Courses</span></div></div><div className="lecturer-stat"><CalendarDays/><div><strong>{schedule.length}</strong><span>Scheduled Classes</span></div></div><div className="lecturer-stat"><UsersRound/><div><strong>{new Set(courses.map(x=>x.academic_period_id)).size}</strong><span>Teaching Periods</span></div></div></div><div className="portal-two"><section className="management-card"><div className="section-title"><div><h2>Teaching Overview</h2><p>Your assigned course offerings in the selected teaching history.</p></div></div>{courses.slice(0,5).map(c=><div className="portal-course-row" key={c.allocation_id}><div><strong>{c.course_code}</strong><span>{c.course_name}</span></div><button className="table-action" onClick={()=>openClass(c)}>Open</button></div>)}</section><section className="management-card"><div className="section-title"><div><h2>Upcoming Timetable</h2><p>Scheduled teaching sessions in the selected periods.</p></div></div>{schedule.slice(0,5).map(x=><div className="portal-course-row" key={x.id}><div><strong>{x.course_code} • {days[x.day_of_week]}</strong><span>{fmt(x.start_time)}–{fmt(x.end_time)} • {x.venue||"Venue not assigned"}</span></div></div>)}{!schedule.length&&<div className="table-empty">No timetable entries found.</div>}</section></div></>}
  {portalView==="courses"&&<section className="management-card"><div className="section-title"><div><h2>My Courses</h2><p>Assigned course offerings for the selected current or historical periods.</p></div></div><div className="responsive-table"><table><thead><tr><th>Course</th><th>Programme</th><th>Period</th><th>Class / Level</th><th>Role</th><th>Action</th></tr></thead><tbody>{courses.map(c=><tr key={c.allocation_id}><td><strong>{c.course_code}</strong><small>{c.course_name}</small></td><td>{c.programme_code||"—"}<small>{c.programme_name||""}</small></td><td>{c.academic_year}<small>{c.academic_period}</small></td><td>Section {c.section_code||"A"}<small>Level {c.level_number||"—"}</small></td><td>{c.allocation_role||"Lecturer"}</td><td><button className="table-action" onClick={()=>openClass(c)}>Open Course</button></td></tr>)}</tbody></table></div></section>}
  {portalView==="timetable"&&<section className="management-card"><div className="section-title"><div><h2>My Timetable</h2><p>Teaching schedule from configured course schedules.</p></div></div><div className="lecturer-schedule-grid">{schedule.map(x=><article className="lecturer-schedule" key={x.id}><div><strong>{x.course_code}</strong><span>{x.course_name}</span></div><p><CalendarDays size={15}/>{days[x.day_of_week]||`Day ${x.day_of_week}`}</p><p><Clock3 size={15}/>{fmt(x.start_time)} – {fmt(x.end_time)}</p><p><MapPin size={15}/>{x.venue||"Venue not assigned"}</p></article>)}</div>{!schedule.length&&<div className="table-empty">No timetable entries found.</div>}</section>}
  {["classes","attendance","results"].includes(portalView)&&<section className="management-card"><div className="section-title"><div><h2>{portalView==="classes"?"Class Lists":portalView==="attendance"?"Attendance":"Course Results"}</h2><p>{portalView==="classes"?"Select a course to open its approved registered class list.":portalView==="attendance"?"Select a course to create sessions and mark attendance.":"Select a course to enter, analyse and submit results."}</p></div></div><div className="portal-course-grid">{courses.map(c=><article className="portal-course-card" key={c.allocation_id}><span>{c.programme_code||"Programme"}</span><h3>{c.course_code}</h3><p>{c.course_name}</p><small>Section {c.section_code||"A"} • Level {c.level_number||"—"} • {c.academic_period}</small><button className="primary-action" onClick={()=>openClass(c)}>Open {portalView==="classes"?"Class List":portalView==="attendance"?"Attendance":"Results"}</button></article>)}</div></section>}
 </div>;

}