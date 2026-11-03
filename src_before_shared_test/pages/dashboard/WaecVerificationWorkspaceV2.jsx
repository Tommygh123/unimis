import {printCurrentView} from "../../lib/printInPlace098";
import {useCallback,useEffect,useMemo,useState} from "react";
import {BadgeCheck,BadgeX,ExternalLink,FileSpreadsheet,ShieldCheck} from "lucide-react";
import {
  createWaecBatch,loadWaecBatches,loadWaecBatchCandidates,
  reconcileWaecBulkBatch,recordWaecVerification,updateWaecBatchStatus
} from "../../services/admissions";

function applicantName(a){return [a?.first_name,a?.middle_name,a?.last_name].filter(Boolean).join(" ")||"Unnamed applicant";}
function csvEscape(v){const s=String(v??"");return /[",\n]/.test(s)?`"${s.replaceAll('"','""')}"`:s;}
function downloadCsv(filename,headers,rows){const csv=[headers,...rows].map(r=>r.map(csvEscape).join(",")).join("\r\n");const blob=new Blob([csv],{type:"text/csv;charset=utf-8"});const url=URL.createObjectURL(blob);const a=document.createElement("a");a.href=url;a.download=filename;a.click();URL.revokeObjectURL(url);}
function parseCsvText(text){const rows=[];let row=[],cell="",quoted=false;for(let i=0;i<text.length;i++){const ch=text[i],next=text[i+1];if(ch==='"'&&quoted&&next==='"'){cell+='"';i++;continue;}if(ch==='"'){quoted=!quoted;continue;}if(ch===','&&!quoted){row.push(cell);cell="";continue;}if((ch==="\n"||ch==="\r")&&!quoted){if(ch==="\r"&&next==="\n")i++;row.push(cell);cell="";if(row.some(v=>String(v).trim()!==""))rows.push(row);row=[];continue;}cell+=ch;}row.push(cell);if(row.some(v=>String(v).trim()!==""))rows.push(row);if(rows.length<2)return{headers:rows[0]||[],rows:[]};const headers=rows[0].map(h=>String(h).trim());return{headers,rows:rows.slice(1).map(values=>Object.fromEntries(headers.map((h,i)=>[h,values[i]??""])))};}
function norm(v){return String(v||"").toLowerCase().replace(/[^a-z0-9]/g,"");}
function findHeader(headers,candidates){const m=new Map(headers.map(h=>[norm(h),h]));for(const c of candidates)if(m.has(norm(c)))return m.get(norm(c));return "";}
function parseResultSummary(value){return String(value||"").split(/[;|]/).map(x=>x.trim()).filter(Boolean).map(part=>{const m=part.match(/^(.+?)[\s:=,-]+(A1|B2|B3|C4|C5|C6|D7|E8|F9)$/i);return m?{subject_name:m[1].trim(),grade:m[2].toUpperCase()}:null;}).filter(Boolean);}
function normalizeReturned(parsed,mapping){const identity=new Set([mapping.index,mapping.year,mapping.name,mapping.examType,mapping.results].filter(Boolean));return parsed.rows.map(raw=>{let subjects=mapping.results?parseResultSummary(raw[mapping.results]):[];if(!subjects.length)subjects=parsed.headers.filter(h=>!identity.has(h)).map(h=>{const grade=String(raw[h]||"").trim().toUpperCase();return /^(A1|B2|B3|C4|C5|C6|D7|E8|F9)$/.test(grade)?{subject_name:h,grade}:null;}).filter(Boolean);return{index_number:String(raw[mapping.index]||"").trim(),exam_year:String(raw[mapping.year]||"").trim(),candidate_name:mapping.name?String(raw[mapping.name]||"").trim():"",exam_type:mapping.examType?String(raw[mapping.examType]||"").trim():"WASSCE",subjects,raw};}).filter(r=>r.index_number&&r.exam_year);}


function pct(n,d){return d?`${((n/d)*100).toFixed(1)}%`:"0.0%";}
function fmtDate(v){return v?new Date(v).toLocaleString():"—";}
function exportBatchReport(batch,candidates){
  const batchRows=candidates.filter(c=>c.batch_id===batch.id);
  const uniqueApplicants=new Set(batchRows.map(c=>c.applicant_id)).size;
  const returned=batchRows.filter(c=>c.reconciliation_status!=="pending"&&c.reconciliation_status!=="not_returned").length;
  const matched=batchRows.filter(c=>c.reconciliation_status==="matched").length;
  const gradeMismatch=batchRows.filter(c=>c.reconciliation_status==="grade_mismatch").length;
  const identityReview=batchRows.filter(c=>c.reconciliation_status==="identity_review").length;
  const notReturned=batchRows.filter(c=>c.reconciliation_status==="not_returned").length;
  const invalid=batchRows.filter(c=>c.reconciliation_status==="invalid_result").length;
  downloadCsv(
    `${batch.batch_number}-reconciliation-report.csv`,
    ["Batch","Provider Reference","Applicants","Sittings Sent","Results Returned","Matched","Grade Mismatch","Identity Review","Not Returned","Invalid","Exceptions","Verification Rate","Return Rate","Status","Exported At","Submitted At","Returned At","Reconciled At"],
    [[
      batch.batch_number,batch.provider_reference||"",uniqueApplicants,batchRows.length,returned,matched,
      gradeMismatch,identityReview,notReturned,invalid,gradeMismatch+identityReview+notReturned+invalid,
      pct(matched,batchRows.length),pct(returned,batchRows.length),batch.status,
      fmtDate(batch.exported_at),fmtDate(batch.submitted_at),fmtDate(batch.returned_at),fmtDate(batch.reconciled_at)
    ]]
  );
}

export default function WaecVerificationWorkspaceV2({data,institutionId,refresh,setMessage,setError,busy,setBusy}){
 const [view,setView]=useState("queue"),[search,setSearch]=useState(""),[cycleId,setCycleId]=useState("all"),[status,setStatus]=useState("all");
 const [selected,setSelected]=useState(()=>new Set()),[batches,setBatches]=useState([]),[candidates,setCandidates]=useState([]),[batchId,setBatchId]=useState("");
 const [csv,setCsv]=useState(null),[mapping,setMapping]=useState({index:"",year:"",name:"",examType:"",results:""});
 const appByApplicant=useMemo(()=>{const m=new Map();(data.applications||[]).forEach(a=>{if(!m.has(a.applicant_id))m.set(a.applicant_id,a)});return m;},[data.applications]);
 const rows=useMemo(()=>data.qualifications.filter(q=>(q.qualification_type||"").toUpperCase()==="WASSCE").map(q=>{const application=appByApplicant.get(q.applicant_id);const applicant=data.applicants.find(a=>a.id===q.applicant_id);const results=data.subjectResults.filter(r=>r.qualification_id===q.id);return{q,application,applicant,results};}).filter(({q,application,applicant})=>application&&(cycleId==="all"||application.admission_cycle_id===cycleId)&&(status==="all"||(q.verification_status||"unverified")===status)&&`${application.application_number||""} ${applicantName(applicant)} ${q.index_number||""}`.toLowerCase().includes(search.trim().toLowerCase())),[data,appByApplicant,cycleId,status,search]);
 const load=useCallback(async()=>{if(!institutionId)return;const[b,c]=await Promise.all([loadWaecBatches(institutionId),loadWaecBatchCandidates(institutionId)]);if(b.error)setError(b.error.message);else setBatches(b.data||[]);if(c.error)setError(c.error.message);else setCandidates(c.data||[]);},[institutionId,setError]);
 useEffect(()=>{load();},[load]);
 const toggle=id=>setSelected(p=>{const n=new Set(p);n.has(id)?n.delete(id):n.add(id);return n;});
 const toggleAll=()=>setSelected(selected.size===rows.length&&rows.length?new Set():new Set(rows.map(r=>r.q.id)));
 function exportRows(chosen,bn){downloadCsv(`unimis-${bn}-waec-batch.csv`,["UniMIS Application","Candidate Name","Index Number","Exam Type","Exam Year","Sitting","Entered Subjects / Grades"],chosen.map(({q,application,applicant,results})=>[application?.application_number||"",applicantName(applicant),q.index_number||"",q.qualification_type||"WASSCE",q.completion_year||"",q.exam_sitting||"",results.map(r=>`${r.subject_name}:${r.grade}`).join("; ")]));}
 async function createBatchNow(){if(!selected.size){setError("Select at least one WASSCE candidate.");return;}setBusy("waec-create");setError("");const r=await createWaecBatch({qualificationIds:[...selected],admissionCycleId:cycleId==="all"?null:cycleId});if(r.error)setError(r.error.message);else{exportRows(rows.filter(x=>selected.has(x.q.id)),r.data.batch_number);await updateWaecBatchStatus({batchId:r.data.id,status:"exported"});setMessage(`WAEC batch ${r.data.batch_number} created and exported.`);setSelected(new Set());setView("batches");await load();}setBusy("");}
 async function record(row,nextStatus){const reference=window.prompt(nextStatus==="verified"?"Enter WAEC verification/reference number:":"Enter WAEC reference or mismatch reason:",row.q.verification_reference||"");if(reference===null)return;const notes=window.prompt("Verification notes (optional):","")??"";setBusy(`waec-${row.q.id}`);const r=await recordWaecVerification({qualificationId:row.q.id,status:nextStatus,method:"waec_portal",reference,notes});if(r.error)setError(r.error.message);else{setMessage(nextStatus==="verified"?"WAEC verification recorded.":"WAEC mismatch recorded.");await refresh();}setBusy("");}
 async function markSubmitted(b){const ref=window.prompt("WAEC/provider batch reference (optional):",b.provider_reference||"");if(ref===null)return;const r=await updateWaecBatchStatus({batchId:b.id,status:"submitted",providerReference:ref});if(r.error)setError(r.error.message);else{setMessage(`${b.batch_number} marked submitted.`);await load();}}
 async function readFile(file){if(!file)return;const p=parseCsvText(await file.text());setCsv(p);setMapping({index:findHeader(p.headers,["Index Number","Index No","Candidate Number","Candidate No","Index"]),year:findHeader(p.headers,["Exam Year","Year","Examination Year"]),name:findHeader(p.headers,["Candidate Name","Name","Full Name"]),examType:findHeader(p.headers,["Exam Type","Examination","Exam"]),results:findHeader(p.headers,["Results","Subjects / Grades","Subjects and Grades","Result"])});}
 async function reconcile(){if(!batchId||!csv?.rows?.length||!mapping.index||!mapping.year){setError("Choose a batch/file and map Index Number + Exam Year.");return;}const normalized=normalizeReturned(csv,mapping);if(!normalized.length){setError("No returned rows could be normalized.");return;}setBusy("waec-reconcile");await updateWaecBatchStatus({batchId,status:"returned"});const r=await reconcileWaecBulkBatch({batchId,rows:normalized});if(r.error)setError(r.error.message);else{setMessage(`Reconciled: ${r.data.matched} matched; ${r.data.exceptions} exceptions.`);setView("exceptions");setCsv(null);await Promise.all([load(),refresh()]);}setBusy("");}
 const verified=data.qualifications.filter(q=>(q.qualification_type||"").toUpperCase()==="WASSCE"&&q.verification_status==="verified").length,mismatch=data.qualifications.filter(q=>(q.qualification_type||"").toUpperCase()==="WASSCE"&&q.verification_status==="mismatch").length,total=data.qualifications.filter(q=>(q.qualification_type||"").toUpperCase()==="WASSCE").length;
 const exceptions=candidates.filter(c=>["grade_mismatch","identity_review","not_returned","invalid_result"].includes(c.reconciliation_status));
 const selectedBatch=batches.find(b=>b.id===batchId);
 const selectedBatchRows=useMemo(()=>candidates.filter(c=>c.batch_id===batchId),[candidates,batchId]);
 const selectedBatchStats=useMemo(()=>{
   const rows=selectedBatchRows, uniqueApplicants=new Set(rows.map(c=>c.applicant_id)).size;
   const matched=rows.filter(c=>c.reconciliation_status==="matched").length;
   const gradeMismatch=rows.filter(c=>c.reconciliation_status==="grade_mismatch").length;
   const identityReview=rows.filter(c=>c.reconciliation_status==="identity_review").length;
   const notReturned=rows.filter(c=>c.reconciliation_status==="not_returned").length;
   const invalid=rows.filter(c=>c.reconciliation_status==="invalid_result").length;
   const returned=rows.filter(c=>c.reconciliation_status!=="pending"&&c.reconciliation_status!=="not_returned").length;
   return {uniqueApplicants,sent:rows.length,returned,matched,gradeMismatch,identityReview,notReturned,invalid,exceptions:gradeMismatch+identityReview+notReturned+invalid};
 },[selectedBatchRows]);
 return <div className="waec-workspace">
  <div className="section-title"><div><h2>WAEC Result Verification</h2><p>Manual RVS, bulk reconciliation and future API verification use one institutional verification record.</p></div><a className="secondary-button" href="https://rvs.waecdirect.org/home/index" target="_blank" rel="noreferrer"><ExternalLink size={16}/>Open WAEC RVS</a></div>
  <div className="waec-subtabs">{[["queue","Verification Queue"],["batches","Bulk Batches"],["exceptions","Reconciliation Exceptions"],["history","Verification History"]].map(([k,l])=><button type="button" key={k} className={view===k?"active":""} onClick={()=>setView(k)}>{l}</button>)}</div>
  <div className="report-summary-grid"><div><span>WASSCE records</span><strong>{total}</strong></div><div><span>Awaiting</span><strong>{total-verified-mismatch}</strong></div><div><span>Verified</span><strong>{verified}</strong></div><div><span>Mismatch</span><strong>{mismatch}</strong></div></div>
  <div className="waec-guidance-card"><ShieldCheck size={22}/><div><strong>API-ready queue</strong><p>When the university receives official WAEC REST API credentials, a server-side Supabase Edge Function can consume the same queue and write the same audit records. Applicant records do not change, and credentials never enter React.</p></div></div>
  {view==="queue"&&<><div className="report-filter-row"><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search applicant/application/index..."/><select value={cycleId} onChange={e=>setCycleId(e.target.value)}><option value="all">All cycles</option>{data.cycles.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select><select value={status} onChange={e=>setStatus(e.target.value)}><option value="all">All statuses</option><option value="unverified">Awaiting verification</option><option value="verified">Verified</option><option value="mismatch">Mismatch</option></select></div><div className="waec-batch-toolbar"><button className="secondary-button" type="button" onClick={toggleAll}>{selected.size===rows.length&&rows.length?"Clear selection":"Select visible"}</button><span>{selected.size} selected</span><button className="primary-button" type="button" disabled={!selected.size||!!busy} onClick={createBatchNow}><FileSpreadsheet size={16}/>Create & Export Bulk Batch</button></div><div className="responsive-table"><table className="academic-table"><thead><tr><th></th><th>Applicant</th><th>WAEC identity</th><th>Entered result</th><th>Status</th><th>Action</th></tr></thead><tbody>{rows.map(row=><tr key={row.q.id}><td><input type="checkbox" checked={selected.has(row.q.id)} onChange={()=>toggle(row.q.id)}/></td><td><strong>{row.application?.application_number}</strong><span className="table-subtext">{applicantName(row.applicant)}</span></td><td><strong>{row.q.index_number||"No index"}</strong><span className="table-subtext">{row.q.completion_year||"—"} • {row.q.exam_sitting||"WASSCE"}</span></td><td><strong>{row.results.length} subject(s)</strong><span className="table-subtext">{row.results.map(r=>`${r.subject_name} ${r.grade}`).join(" • ")||"No grades"}</span></td><td><span className={`status-pill ${row.q.verification_status||"unverified"}`}>{row.q.verification_status||"unverified"}</span></td><td><div className="queue-actions"><button className="table-action success" type="button" onClick={()=>record(row,"verified")}><BadgeCheck size={14}/>Verified</button><button className="table-action danger" type="button" onClick={()=>record(row,"mismatch")}><BadgeX size={14}/>Mismatch</button></div></td></tr>)}{!rows.length&&<tr><td colSpan="6" className="table-empty">No paid/submitted WASSCE records.</td></tr>}</tbody></table></div></>}
  {view==="batches"&&<>
  <div className="waec-batch-list">{batches.map(b=><article key={b.id} className={batchId===b.id?"selected":""} onClick={()=>setBatchId(b.id)}>
    <div><strong>{b.batch_number}</strong><span>{b.candidate_count} sittings • {b.status}</span></div>
    <div><span>Matched {b.matched_count}</span><span>Exceptions {b.exception_count}</span>
      {b.status==="exported"&&<button className="table-action" type="button" onClick={e=>{e.stopPropagation();markSubmitted(b)}}>Mark submitted</button>}
    </div>
  </article>)}{!batches.length&&<div className="table-empty">No bulk batches yet.</div>}</div>

  {selectedBatch&&<section className="admission-subcard waec-stats-card">
    <div className="section-title">
      <div><h3>{selectedBatch.batch_number} — Batch Statistics</h3><p>{selectedBatch.provider_reference?`Provider ref: ${selectedBatch.provider_reference}`:"No provider reference recorded yet."}</p></div>
      <div className="queue-actions">
        <button type="button" className="secondary-button" onClick={()=>exportBatchReport(selectedBatch,candidates)}>Export report CSV</button>
        <button type="button" className="secondary-button" onClick={()=>printCurrentView("UniMIS WaecVerificationWorkspaceV2 Report")}>Print report</button>
      </div>
    </div>
    <div className="waec-stats-grid">
      <div><span>Unique applicants</span><strong>{selectedBatchStats.uniqueApplicants}</strong></div>
      <div><span>WAEC sittings sent</span><strong>{selectedBatchStats.sent}</strong></div>
      <div><span>Results returned</span><strong>{selectedBatchStats.returned}</strong></div>
      <div><span>Successfully verified</span><strong>{selectedBatchStats.matched}</strong></div>
      <div><span>Grade mismatches</span><strong>{selectedBatchStats.gradeMismatch}</strong></div>
      <div><span>Identity review</span><strong>{selectedBatchStats.identityReview}</strong></div>
      <div><span>Not returned</span><strong>{selectedBatchStats.notReturned}</strong></div>
      <div><span>Exceptions total</span><strong>{selectedBatchStats.exceptions}</strong></div>
      <div><span>Verification rate</span><strong>{pct(selectedBatchStats.matched,selectedBatchStats.sent)}</strong></div>
      <div><span>Return rate</span><strong>{pct(selectedBatchStats.returned,selectedBatchStats.sent)}</strong></div>
    </div>
    <div className="waec-meta-grid">
      <div><span>Status</span><strong>{selectedBatch.status}</strong></div>
      <div><span>Exported</span><strong>{fmtDate(selectedBatch.exported_at)}</strong></div>
      <div><span>Submitted</span><strong>{fmtDate(selectedBatch.submitted_at)}</strong></div>
      <div><span>Returned</span><strong>{fmtDate(selectedBatch.returned_at)}</strong></div>
      <div><span>Reconciled</span><strong>{fmtDate(selectedBatch.reconciled_at)}</strong></div>
    </div>
    <div className="responsive-table waec-report-table"><table className="academic-table">
      <thead><tr><th>Candidate</th><th>Index / Year</th><th>Outcome</th><th>Official name</th><th>Comparison</th></tr></thead>
      <tbody>{selectedBatchRows.map(c=><tr key={c.id}>
        <td>{c.applicant_name||"—"}</td>
        <td>{c.index_number||"—"} / {c.exam_year||"—"}</td>
        <td><span className={`status-pill ${c.reconciliation_status}`}>{c.reconciliation_status.replaceAll("_"," ")}</span></td>
        <td>{c.official_candidate_name||"—"}</td>
        <td>{c.comparison_result?.matched_subject_count??"—"} / {c.comparison_result?.entered_subject_count??"—"} subjects matched</td>
      </tr>)}{!selectedBatchRows.length&&<tr><td colSpan="5" className="table-empty">Select a batch to view its reconciliation report.</td></tr>}</tbody>
    </table></div>
  </section>}

  <section className="admission-subcard waec-return-card">
    <h3>Import returned WAEC CSV</h3>
    <label>Batch<select value={batchId} onChange={e=>setBatchId(e.target.value)}><option value="">Choose batch…</option>{batches.map(b=><option key={b.id} value={b.id}>{b.batch_number} — {b.status}</option>)}</select></label>
    <label>Returned CSV<input type="file" accept=".csv,text/csv" onChange={e=>readFile(e.target.files?.[0])}/></label>
    {csv&&<div className="waec-mapping-grid">{[["index","Index Number"],["year","Exam Year"],["name","Candidate Name"],["examType","Exam Type"],["results","Combined Results"]].map(([key,label])=><label key={key}>{label}<select value={mapping[key]} onChange={e=>setMapping({...mapping,[key]:e.target.value})}><option value="">{key==="results"?"Auto-detect subject columns":"Map column…"}</option>{csv.headers.map(h=><option key={h}>{h}</option>)}</select></label>)}</div>}
    <button className="primary-button" type="button" disabled={!batchId||!csv||!!busy} onClick={reconcile}><ShieldCheck size={16}/>Reconcile Returned Results</button>
  </section>
</>}

{view==="exceptions"&&<div className="responsive-table"><table className="academic-table"><thead><tr><th>Batch</th><th>Candidate</th><th>Index / Year</th><th>Exception</th><th>Comparison</th></tr></thead><tbody>{exceptions.map(c=><tr key={c.id}><td>{batches.find(b=>b.id===c.batch_id)?.batch_number||"—"}</td><td>{c.applicant_name||"—"}</td><td>{c.index_number||"—"} / {c.exam_year||"—"}</td><td><span className={`status-pill ${c.reconciliation_status}`}>{c.reconciliation_status.replaceAll("_"," ")}</span></td><td>{c.comparison_result?.matched_subject_count??"—"} / {c.comparison_result?.entered_subject_count??"—"} subjects matched</td></tr>)}{!exceptions.length&&<tr><td colSpan="5" className="table-empty">No reconciliation exceptions.</td></tr>}</tbody></table></div>}
  {view==="history"&&<div className="responsive-table"><table className="academic-table"><thead><tr><th>Batch</th><th>Candidate</th><th>Index / Year</th><th>Outcome</th><th>Reconciled</th></tr></thead><tbody>{candidates.filter(c=>c.reconciliation_status!=="pending").map(c=><tr key={c.id}><td>{batches.find(b=>b.id===c.batch_id)?.batch_number||"—"}</td><td>{c.applicant_name||"—"}</td><td>{c.index_number||"—"} / {c.exam_year||"—"}</td><td>{c.reconciliation_status.replaceAll("_"," ")}</td><td>{c.reconciled_at?new Date(c.reconciled_at).toLocaleString():"—"}</td></tr>)}{!candidates.some(c=>c.reconciliation_status!=="pending")&&<tr><td colSpan="5" className="table-empty">No bulk verification history.</td></tr>}</tbody></table></div>}
 </div>;
}
