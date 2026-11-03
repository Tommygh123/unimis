import {printAcademicDocument115,academicPeriodKey} from "./academicDocumentWorkspace115";
export function printResultSlip({student,enrolment,period,results=[],gpa={},institution}){
 const year=period?.academic_year||gpa.academic_year||results[0]?.academic_year||"",term=period?.academic_period||gpa.academic_period||results[0]?.academic_period||"";
 const rows=results.map(r=>({...r,status:r.status||r.result_status||"published",academic_year:r.academic_year||year,academic_period:r.academic_period||term}));
 return printAcademicDocument115({profile:{...student,...enrolment,results:rows,gpa_history:[{...gpa,academic_year:year,academic_period:term}]},institution,type:"result_slip",period:`${year}||${term}`});
}
export function printAcademicTranscript({student,enrolment,results=[],gpaSummary={},graduation,institution}){
 const history=gpaSummary.latest?[gpaSummary.latest,...(gpaSummary.history||[]).filter(g=>academicPeriodKey(g)!==academicPeriodKey(gpaSummary.latest))]:gpaSummary.history||[];
 return printAcademicDocument115({profile:{...student,...enrolment,results:results.map(r=>({...r,status:r.status||r.result_status||"published"})),gpa_history:history,graduation},institution,type:"transcript"});
}
