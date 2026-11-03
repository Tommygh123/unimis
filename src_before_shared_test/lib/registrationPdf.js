import {jsPDF} from "jspdf";
export function downloadRegistrationSlipPdf(data){
 const h=data?.header||{},courses=data?.courses||[];const doc=new jsPDF({unit:"mm",format:"a4"});
 doc.setFont("helvetica","bold");doc.setFontSize(17);doc.text("AG Technical University",105,18,{align:"center"});
 doc.setFontSize(13);doc.text("STUDENT COURSE REGISTRATION SLIP",105,29,{align:"center"});
 doc.setLineWidth(.5);doc.line(18,34,192,34);let y=45;
 const row=(a,b)=>{doc.setFont("helvetica","bold");doc.text(a,18,y);doc.setFont("helvetica","normal");doc.text(String(b||"—"),62,y);y+=7;};
 row("Student Number",h.student_number);row("Student",[h.first_name,h.middle_name,h.last_name].filter(Boolean).join(" "));row("Programme",`${h.programme_code||""} — ${h.programme_name||""}`);row("Academic Year",h.academic_year);row("Academic Period",h.academic_period);row("Level",h.current_level);row("Status",h.registration_status);
 y+=7;doc.setFont("helvetica","bold");doc.text("Registered Courses",18,y);y+=8;doc.setFontSize(9);
 courses.forEach((c,i)=>{if(y>275){doc.addPage();y=20;}doc.setFont("helvetica","bold");doc.text(`${i+1}. ${c.course_code}`,18,y);doc.setFont("helvetica","normal");doc.text(`${c.course_name}  (${c.credit_hours} credits)`,48,y);y+=6;});
 y+=5;doc.setFont("helvetica","bold");doc.text(`Total Credits: ${courses.reduce((s,c)=>s+Number(c.credit_hours||0),0)}`,18,y);
 doc.setFont("helvetica","normal");doc.setFontSize(8);doc.text(`Generated ${new Date().toLocaleString()} • UniMIS`,18,287);
 doc.save(`${h.student_number||"student"}-${h.academic_year||"registration"}-${h.academic_period||"period"}-registration-slip.pdf`.replace(/[^a-zA-Z0-9._-]+/g,"-"));
}
