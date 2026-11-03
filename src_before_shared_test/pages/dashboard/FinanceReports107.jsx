import {FinanceGauge125,FinanceDonut125} from '../../components/finance/FinanceVisuals125';
import {groupReportRows125} from '../../lib/financeVisuals125';
import ApplicationRevenue124 from './ApplicationRevenue124';
import {useEffect,useMemo,useRef,useState} from "react";
import {reportSections} from "../../lib/accountsNavigation";
import "../../styles/accounts-workspaces.css";
import {useSearchParams} from "react-router-dom";
import {BarChart3,Download,FileText,RefreshCw} from "lucide-react";
import Toast from "../../components/Toast";
import {loadFinanceAnalytics,loadFinanceAnalyticsFilters} from "../../services/finance078";
import {printHtmlInPlace} from "../../lib/printInPlace098";
import "../../styles/finance-098.css";
import "../../styles/finance-reports-107.css";

const defaults=()=>({from:`${new Date().getFullYear()}-01-01`,to:new Date().toISOString().slice(0,10),academic_year_id:"",academic_period_id:"",programme_id:"",level:"",student_type:"",fee_type_id:"",payment_method:"",status:"",currency:"GHS"});
const tabs=reportSections;
const feeHeaders=[["Student No.","student_number"],["Student","student_name"],["Programme","programme_code"],["Level","level"],["Billed","billed"],["Collected","paid"],["Outstanding","outstanding"],["Waiver","waiver"]];
const componentHeaders=[["Component","fee_type"],["Billed","billed"],["Collected","paid"],["Outstanding","outstanding"],["Waiver","waiver"],["Collection %","rate"]];
const paymentHeaders=[["Date","payment_date"],["Reference","payment_reference"],["Student No.","student_number"],["Student","student_name"],["Method","payment_method"],["Amount","amount"]];
const expenseHeaders=[["Date","expense_date"],["Reference","reference"],["Description","description"],["Payee","payee"],["Method","payment_method"],["Amount","amount"]];
const ledgerHeaders=[["Date","journal_date"],["Journal","journal_number"],["Reference","reference"],["Code","code"],["Account","name"],["Description","description"],["Debit","debit"],["Credit","credit"]];
const trialHeaders=[["Code","code"],["Account","name"],["Debit","debit"],["Credit","credit"],["Net Debit / (Credit)","balance"]];
const statementHeaders=[["Code","code"],["Account","name"],["Type","account_type"],["Amount","amount"]];
const monetary=new Set(["billed","paid","outstanding","amount","debit","credit","balance","waiver"]);
const money=v=>`GHS ${Number(v||0).toLocaleString(undefined,{minimumFractionDigits:2,maximumFractionDigits:2})}`;
const esc=v=>String(v??"—").replace(/[&<>"']/g,m=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[m]));
const display=(v,k)=>monetary.has(k)?Number(v||0).toLocaleString(undefined,{minimumFractionDigits:2,maximumFractionDigits:2}):v??"—";
const sum=(rows,k)=>rows.reduce((n,r)=>n+Number(r[k]||0),0);
function exportRows(headers,rows){if(!rows.length||headers.some(h=>h[1]==="account_type")||!headers.some(h=>monetary.has(h[1])))return rows;const total={[headers[0][1]]:"TOTAL"};for(const [,key] of headers)if(monetary.has(key))total[key]=sum(rows,key);if(headers.some(h=>h[1]==="rate"))total.rate=sum(rows,"billed")>0?(sum(rows,"paid")/sum(rows,"billed")*100).toFixed(1):"0.0";return [...rows,total]}
function academicDefaults(options){const y=(options.academic_years||[]).find(x=>x.is_current)||(options.academic_years||[])[0],p=(options.periods||[]).find(x=>x.academic_year_id===y?.id&&x.is_current)||(options.periods||[]).find(x=>x.academic_year_id===y?.id);return {...defaults(),academic_year_id:y?.id||"",academic_period_id:p?.id||"",from:p?.start_date||y?.start_date||defaults().from,to:p?.end_date||y?.end_date||defaults().to}}

export default function FinanceReports107(){
 const [params,setParams]=useSearchParams();
 const tab=tabs.some(([key])=>key===params.get("report"))?params.get("report"):"dashboard";
 const [filters,setFilters]=useState(defaults),[applied,setApplied]=useState(null);
 const [options,setOptions]=useState({academic_years:[],periods:[],programmes:[],fee_types:[],student_types:[],levels:[]});
 const [data,setData]=useState(null),[busy,setBusy]=useState(false),[error,setError]=useState("");
 const [student,setStudent]=useState(""),[search,setSearch]=useState("");
 const request=useRef(0);
 async function load(next){
  if(!next.from||!next.to||next.from>next.to){setError("Select a valid date range: From must be on or before To.");return}
  const id=++request.current;setBusy(true);setError("");
  const r=await loadFinanceAnalytics(next);
  if(id!==request.current)return;
  setBusy(false);
  if(r.error)setError(r.error.message);else{setData(r.data||{});setApplied({...next});setStudent("")}
 }
 useEffect(()=>{let alive=true;loadFinanceAnalyticsFilters().then(r=>{if(!alive)return;if(r.error){setError(r.error.message);load(defaults());return}const o=r.data||{};setOptions(o);const y=(o.academic_years||[]).find(x=>x.is_current)||(o.academic_years||[])[0],period=(o.periods||[]).find(x=>x.academic_year_id===y?.id&&x.is_current)||(o.periods||[]).find(x=>x.academic_year_id===y?.id);const next={...defaults(),academic_year_id:y?.id||"",academic_period_id:period?.id||"",from:period?.start_date||y?.start_date||defaults().from,to:period?.end_date||y?.end_date||defaults().to};setFilters(next);load(next)});return()=>{alive=false;request.current++}},[]);
 const periods=useMemo(()=>(options.periods||[]).filter(x=>!filters.academic_year_id||x.academic_year_id===filters.academic_year_id),[options.periods,filters.academic_year_id]);
 const s=data?.summary||{},students=data?.students||[];
 const institutionReport=["expenses","ledger","financial"].includes(tab);
 const rows=students.filter(r=>`${r.student_number} ${r.student_name} ${r.programme_code}`.toLowerCase().includes(search.toLowerCase()));
 const components=(data?.fee_components||[]).map(r=>({...r,rate:Number(r.billed)>0?(Number(r.paid)/Number(r.billed)*100).toFixed(1):"0.0"}));
 function select(key,label,list,valueKey="id",labelKey="name"){return <label>{label}<select disabled={institutionReport} value={filters[key]} onChange={e=>setFilters(f=>({...f,[key]:e.target.value,...(key==="academic_year_id"?{academic_period_id:""}:{})}))}><option value="">All {label.toLowerCase()}</option>{list.map(x=>typeof x==="object"?<option key={x[valueKey]} value={x[valueKey]}>{x[labelKey]}</option>:<option key={x} value={x}>{String(x).replaceAll("_"," ")}</option>)}</select></label>}
 function scope(institution=false){
  if(!applied)return "";
  if(institution)return `Institution-wide • ${applied.from} to ${applied.to} • GHS functional currency. Student and payment filters do not apply.`;
  const studentName=tab==="statements"?students.find(x=>x.student_id===student):null;
  const names=[['academic_year_id','academic_years'],['academic_period_id','periods'],['programme_id','programmes'],['fee_type_id','fee_types']].map(([key,list])=>(options[list]||[]).find(x=>x.id===applied[key])?.name).filter(Boolean);
  return `${applied.from} to ${applied.to} • GHS • ${[...names,applied.level,applied.student_type,applied.payment_method,applied.status,studentName?`${studentName.student_number} — ${studentName.student_name}`:""].filter(Boolean).join(" • ")||"All students and fee components"}`;
 }
 function csv(title,headers,reportRows,institution,groupKey=""){
  const safe=v=>{const str=String(v??"");return /^[=+@\-\t\r]/.test(str)?`'${str}`:str};
  const records=[[title],[scope(institution)],[...(groupKey?["Group"]:[]),...headers.map(h=>h[0])],...exportRows(headers,reportRows).map(r=>[...(groupKey?[r[groupKey]??""]:[]),...headers.map(h=>r[h[1]]??"")])];
  const text="\uFEFF"+records.map(row=>row.map(v=>`"${safe(v).replaceAll('"','""')}"`).join(",")).join("\r\n");
  const url=URL.createObjectURL(new Blob([text],{type:"text/csv;charset=utf-8"}));const a=document.createElement("a");a.href=url;a.download=`UniMIS_${title.replace(/[^a-z0-9]+/gi,"_")}.csv`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
 }
 function pdf(title,headers,reportRows,institution,groupKey=""){
  const html=`<h1>${esc(title)}</h1><p>${esc(scope(institution))}</p><table><thead><tr>${headers.map(h=>`<th>${esc(h[0])}</th>`).join("")}</tr></thead><tbody>${groupReportRows125(reportRows,groupKey?[groupKey]:[]).map(([group,members])=>`${groupKey?`<tr><td colspan="${headers.length}" style="background:#dfeaf5;font-weight:bold">${esc(group)}</td></tr>`:""}${members.map(r=>`<tr>${headers.map(h=>`<td>${esc(display(r[h[1]],h[1]))}</td>`).join("")}</tr>`).join("")}`).join("")||`<tr><td colspan="${headers.length}">No records</td></tr>`}</tbody><tfoot>${exportRows(headers,reportRows).slice(reportRows.length).map(r=>`<tr>${headers.map(h=>`<td>${esc(display(r[h[1]],h[1]))}</td>`).join("")}</tr>`).join("")}</tfoot></table>`;
  printHtmlInPlace(title,html,"h1{color:#173f70}table{width:100%;border-collapse:collapse;font-size:10px}.num{text-align:right}th{background:#173f70;color:white;text-align:left}th,td{padding:7px;border-bottom:1px solid #dbe5ee}");
 }
 const report=(title,headers,reportRows,institution=false,onRow)=> <Report key={title} title={title} headers={headers} rows={reportRows} note={scope(institution)} busy={busy} onRow={onRow} onCsv={groupKey=>csv(title,headers,reportRows,institution,groupKey)} onPdf={groupKey=>pdf(title,headers,reportRows,institution,groupKey)}/>;
 const statements=(data?.payments||[]).filter(r=>r.student_id===student);
 const income=data?.income||[],position=data?.position||[];
 const incomeNet=sum(income.filter(r=>r.account_type==="income"),"amount")-sum(income.filter(r=>r.account_type==="expense"),"amount");
 if(tab==="application-revenue")return <ApplicationRevenue124/>;
 return <section className="finance098 reports107">
  <Toast message={error} type="error" onClose={()=>setError("")}/>
  <header className="reports-hero107"><div><span>ACCOUNTS & FINANCE / REPORTS & ANALYTICS</span><h1>{tabs.find(([key])=>key===tab)?.[1]}</h1><p>Financial reporting and management insights</p></div><div className="report-readonly110"><BarChart3 size={23}/><span>REPORT WORKSPACE</span></div></header>
  <nav className="finance-tabs098" aria-label="Accounts reports">{tabs.map(([key,label])=><button key={key} className={`primary ${tab===key?"active":""}`} aria-current={tab===key?"page":undefined} onClick={()=>{setParams({report:key});setSearch("")}}>{label}</button>)}</nav>
  <div className="report-context110"><strong>{institutionReport?"Institution-wide Financial Reporting":[(options.academic_years||[]).find(x=>x.id===applied?.academic_year_id)?.name||"All Academic Years",(options.periods||[]).find(x=>x.id===applied?.academic_period_id)?.name||"All Periods",(options.programmes||[]).find(x=>x.id===applied?.programme_id)?.name||"All Programmes"].join(" • ")}</strong><span>Currency: GHS</span></div>
  <form className="report-filter-panel110" onSubmit={e=>{e.preventDefault();load(filters)}}>
   <div className="report-filter-title110"><h2>Report Filters</h2><span>Choose the academic scope and reporting period</span></div>
   <div className="report-filters107">
    {select("academic_year_id","Academic Year",options.academic_years||[])}
    {select("academic_period_id","Semester / Period",periods)}
    {select("programme_id","Programme",options.programmes||[])}
    {select("level","Level",options.levels||[])}
    <label>Date From<input required type="date" value={filters.from} onChange={e=>setFilters({...filters,from:e.target.value})}/></label>
    <label>Date To<input required type="date" value={filters.to} onChange={e=>setFilters({...filters,to:e.target.value})}/></label>
    {select("student_type","Student Type",options.student_types||[])}
    {select("fee_type_id","Fee Component",options.fee_types||[])}
    {select("payment_method","Period Receipt Method",["cash","mobile_money","bank_transfer","card","cheque","online","scholarship","other"])}
    {select("status","Balance Status",["outstanding","settled"])}
   </div>
   <div className="report-filter-actions110"><span>{applied?`${applied.from} — ${applied.to}`:"Select a period"}{applied&&JSON.stringify(filters)!==JSON.stringify(applied)&&" • Unapplied changes"}</span><button type="button" className="mini098" disabled={busy} onClick={()=>{const next=academicDefaults(options);setFilters(next);setSearch("");load(next)}}>Reset Filters</button><button className="finance-btn098" disabled={busy}><RefreshCw size={15}/>{busy?"Loading…":"Apply Filters"}</button></div>
  </form>
  <details className="report-basis110"><summary>Report basis and allocation</summary><p>Fees cover invoices issued in the selected date range. Collected excludes non-cash waivers and includes completed payments up to the end date; payment analysis shows receipts within the date range. Billed equals collected plus waivers and outstanding. Waiver includes invoice concessions and recorded non-cash waivers. Component collections and waivers are allocated proportionally to invoice line values. Student filters apply to fee reports; journal statements and expenses cover the whole institution. Historical edits use current records.</p></details>
  {busy&&<p role="status">Loading financial reports…</p>}
  {!data&&!busy?<div className="finance-card098">Reports could not be loaded. Apply filters to retry after checking the reporting migration.</div>:data&&<>
  {["dashboard","collection","components","outstanding","payments"].includes(tab)&&<div className="report-kpis107">{[["Total Billed",money(s.billed)],["Total Collected",money(s.paid)],["Outstanding",money(s.outstanding)],["Waivers / Concessions",money(s.waiver)],["Collection Rate",`${Number(s.billed)>0?(Number(s.paid)/Number(s.billed)*100).toFixed(1):"0.0"}%`]].map(([label,value])=><article key={label}><BarChart3/><span>{label}</span><strong>{value}</strong></article>)}</div>}
  {["dashboard","revenue"].includes(tab)&&<article className="finance-card098"><h2>Application Fee Income — {money(income.find(x=>x.code==="4200")?.amount)}</h2><p>Institution-wide net ledger income for the applied dates, separate from student tuition collections. Includes verified fees received before submission and journal reversals.</p><button className="finance-btn098" onClick={()=>setParams({report:"application-revenue"})}>Application Fee Revenue / Submitted Applicants</button></article>}
  {["dashboard","collection","components","outstanding"].includes(tab)&&<div className="finance-visual-grid125"><FinanceGauge125 title="Fee Collection Performance" value={s.paid} total={s.billed} note="Collected / billed for the applied academic and fee filters. Waivers are not cash collected."/><FinanceDonut125 title="Billed Fees — Collection and Balance" items={[{label:"Collected",value:s.paid,colour:"#0f8a75"},{label:"Waivers / concessions",value:s.waiver,colour:"#d99124"},{label:"Outstanding",value:s.outstanding,colour:"#cd4b60"}]} note="Actual report totals. Voided receipts are excluded from completed collections."/></div>}
  {tab==="dashboard"&&<div className="reports-grid107"><Bars title="Monthly Collections" rows={data.trend||[]} label="month"/><Bars title="Payment Methods" rows={data.methods||[]} label="payment_method"/>{report("Programme & Level Collections",[["Programme","programme_code"],["Level","level"],["Billed","billed"],["Paid","paid"],["Outstanding","outstanding"]],data.programmes||[])}{report("Fee Component Overview",componentHeaders,components,false,r=>{const next={...applied,fee_type_id:r.fee_type_id||""};setFilters(next);load(next);setParams({report:"collection"})})}</div>}
  {["collection","outstanding"].includes(tab)&&<><label className="report-search108">Search students<input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Student number, name or programme"/></label>{report(tab==="collection"?"Fee Collection Analysis":"Outstanding Fees",feeHeaders,tab==="outstanding"?rows.filter(r=>Number(r.outstanding)>0):rows,false,r=>{setStudent(r.student_id);setParams({report:"statements"})})}</>}
  {tab==="components"&&<><p className="report-note108">Amounts in GHS. Select a component to drill into programme, level and student detail.</p>{report("Fee Component Analysis",componentHeaders,components,false,r=>{const next={...applied,fee_type_id:r.fee_type_id||""};setFilters(next);load(next);setParams({report:"collection"})})}</>}
  {tab==="statements"&&<><label className="report-search108">Student<select value={student} onChange={e=>setStudent(e.target.value)}><option value="">Select a student</option>{students.map(r=><option key={r.student_id} value={r.student_id}>{r.student_number} — {r.student_name}</option>)}</select></label>{student?<>{report("Student Account Summary",feeHeaders,students.filter(r=>r.student_id===student))}{report("Student Invoice Details",[["Date","invoice_date"],["Invoice","invoice_number"],["Billed","billed"],["Collected","paid"],["Outstanding","outstanding"],["Waiver","waiver"],["Status","status"]],(data.invoices||[]).filter(r=>r.student_id===student))}{report("Student Payments in Selected Period",paymentHeaders,statements)}</>:<div className="finance-card098">Select a student to review the account summary and period payments.</div>}</>}
  {tab==="payments"&&<><Bars title="Collections by Payment Method" rows={data.methods||[]} label="payment_method"/>{report("Payment Analysis",paymentHeaders,data.payments||[])}</>}
  {tab==="revenue"&&<>{report("Fee Collections by Month",[["Month","month"],["Collected","amount"]],data.trend||[])}{report("Posted Revenue Accounts",statementHeaders,income.filter(r=>r.account_type==="income"),true)}</>}
  {tab==="expenses"&&<>{report("Expense Analysis",expenseHeaders,data.expenses||[],true)}{report("Posted Expense Accounts",statementHeaders,income.filter(r=>r.account_type==="expense"),true)}</>}
  {tab==="ledger"&&<>{report("General Ledger",ledgerHeaders,data.ledger||[],true)}{report("Trial Balance — Period Movements",trialHeaders,data.trial_balance||[],true)}</>}
  {tab==="financial"&&<><p className="report-note108">Financial statements use posted journals once, including automatic postings, to avoid double-counting payments and expenses. They cover the whole institution in its GHS functional currency. The position includes all posted entries up to the selected end date; the income statement covers the selected period.</p>{report("Income Statement",statementHeaders,[...income,{name:"Net Surplus / (Deficit)",amount:incomeNet}],true)}{report("Statement of Financial Position",statementHeaders,[...position,{name:"Total Assets",amount:sum(position.filter(r=>r.account_type==="asset"),"amount")},{name:"Total Liabilities & Equity",amount:sum(position.filter(r=>r.account_type!=="asset"),"amount")}],true)}</>}
  </>}
 </section>
}
function Report({title,headers,rows,note,onCsv,onPdf,busy,onRow}){
 const groupOptions=headers.filter(([,key])=>['programme_code','level','academic_year','academic_period','payment_method','status','account_type'].includes(key));
 const [groupBy,setGroupBy]=useState(headers.some(([,key])=>key==='programme_code')?'programme_code':''),[page,setPage]=useState(0);const orderedGroups=groupReportRows125(rows,groupBy?[groupBy]:[]);const orderedRows=orderedGroups.flatMap(([,members])=>members);const size=25,pages=Math.max(1,Math.ceil(rows.length/size)),current=Math.min(page,pages-1);
 return <article className="finance-card098"><div className="finance-title098"><div><h2>{title}</h2><p>{rows.length} row(s)</p></div><div className="finance-actions098"><button disabled={busy} className="export-excel121" onClick={()=>onCsv(groupBy)}><Download size={14}/>Excel (CSV)</button><button disabled={busy} className="export-pdf121" onClick={()=>onPdf(groupBy)}><FileText size={14}/>PDF</button></div></div><p className="report-note108">{note}</p>{groupOptions.length>0&&<label className="report-group-control125">Group view<select value={groupBy} onChange={e=>{setGroupBy(e.target.value);setPage(0)}}><option value="">Ungrouped</option>{groupOptions.map(([label,key])=><option key={key} value={key}>{label}</option>)}</select></label>}<div className="table-scroll098"><table><thead><tr>{headers.map(h=><th className={monetary.has(h[1])||h[1]==="rate"?"report-number110":""} key={h[1]}>{h[0]}</th>)}{onRow&&<th>Details</th>}</tr></thead><tbody>{orderedRows.slice(current*size,(current+1)*size).flatMap((r,i)=>[...(groupBy&&(i===0||r[groupBy]!==orderedRows[current*size+i-1]?.[groupBy])?[<tr className="report-group125" key={`group-${current*size+i}`}><td colSpan={headers.length+(onRow?1:0)}>{r[groupBy]??"Not recorded"}</td></tr>]:[]),<tr key={current*size+i}>{headers.map(h=><td className={monetary.has(h[1])||h[1]==="rate"?"report-number110":""} key={h[1]}>{display(r[h[1]],h[1])}{h[1]==="rate"?"%":""}</td>)}{onRow&&<td><button className="mini098" disabled={busy} onClick={()=>onRow(r)}>View</button></td>}</tr>])}{!rows.length&&<tr><td colSpan={headers.length+(onRow?1:0)}>No records match the applied filters.</td></tr>}</tbody>{rows.length>0&&headers.some(h=>monetary.has(h[1]))&&!headers.some(h=>h[1]==="account_type")&&<tfoot><tr>{headers.map((h,i)=><td className={monetary.has(h[1])||h[1]==="rate"?"report-number110":""} key={h[1]}>{i===0?"TOTAL":monetary.has(h[1])?display(sum(rows,h[1]),h[1]):h[1]==="rate"?`${sum(rows,"billed")>0?(sum(rows,"paid")/sum(rows,"billed")*100).toFixed(1):"0.0"}%`:""}</td>)}{onRow&&<td/>}</tr></tfoot>}</table></div>{pages>1&&<div className="report-pagination108"><button disabled={!current} onClick={()=>setPage(current-1)}>Previous</button><span>Page {current+1} of {pages}</span><button disabled={current>=pages-1} onClick={()=>setPage(current+1)}>Next</button></div>}</article>
}
function Bars({title,rows,label}){const max=Math.max(1,...rows.map(r=>Number(r.amount)));return <article className="finance-card098"><h2>{title}</h2>{!rows.length?<p>No collections match the applied filters.</p>:rows.map(r=><div className="report-bar108" key={r[label]}><div><span>{String(r[label]||"Unspecified").replaceAll("_"," ")}</span><strong>{money(r.amount)}</strong></div><progress max={max} value={Number(r.amount)} aria-label={`${r[label]}: ${money(r.amount)}`}/></div>)}</article>}
