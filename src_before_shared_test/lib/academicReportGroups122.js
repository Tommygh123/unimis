export const academicGroupLabel122=r=>[r.academic_year,r.academic_period,r.faculty_name,r.department_name].filter(Boolean).join(' • ')||'Current / unassigned group';
export const sortAcademicRows122=rows=>[...rows].sort((a,b)=>academicGroupLabel122(a).localeCompare(academicGroupLabel122(b),undefined,{numeric:true}));
