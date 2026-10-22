export function matchesAttendanceStudent144(row,query){
 const normalize=value=>String(value??'').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^\p{L}\p{N}]+/gu,' ').trim();
 const haystack=normalize([row.student_number,row.student_name].join(' '));
 return normalize(query).split(/\s+/).filter(Boolean).every(word=>haystack.includes(word));
}
