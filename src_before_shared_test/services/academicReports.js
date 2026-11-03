import {supabase} from "../lib/supabase";
const wrap=async p=>{try{const {data,error}=await p;return {data,error}}catch(error){return {data:null,error}}};
export const loadReportFilters=()=>wrap(supabase.rpc("unimis_academic_intelligence_filters"));
export const loadAcademicReport=(report,f)=>wrap(supabase.rpc("unimis_academic_report",{p_report:report,p_academic_year_id:f.year||null,p_academic_period_id:f.period||null,p_faculty_id:f.faculty||null,p_department_id:f.department||null,p_programme_id:f.programme||null,p_level:f.level?Number(f.level):null,p_status:f.status||null}));
