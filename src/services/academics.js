import { supabase } from "../lib/supabase";

const TABLES = {
  years: "academic_years",
  periods: "academic_periods",
  faculties: "faculties",
  schools: "schools",
  departments: "departments",
  programmes: "programmes",
  courses: "courses",
  curriculum: "programme_courses",
  offerings: "course_offerings",
  lecturers: "course_lecturers",
  schedules: "course_schedules",
};

export async function loadAcademicSetup(institutionId) {
  const queries = {
    years: supabase
      .from("academic_years")
      .select("*")
      .eq("institution_id", institutionId)
      .order("start_date", { ascending: false }),

    periods: supabase
      .from("academic_periods")
      .select("*,academic_year:academic_years(id,name)")
      .eq("institution_id", institutionId)
      .order("start_date", { ascending: false }),

    faculties: supabase
      .from("faculties")
      .select("*")
      .eq("institution_id", institutionId)
      .order("name"),

    schools: supabase
      .from("schools")
      .select("*,faculty:faculties(id,name,code)")
      .eq("institution_id", institutionId)
      .order("name"),

    departments: supabase
      .from("departments")
      .select("*,faculty:faculties(id,name,code),school:schools(id,name,code)")
      .eq("institution_id", institutionId)
      .order("name"),

    programmes: supabase
      .from("programmes")
      .select("*,department:departments(id,name,code)")
      .eq("institution_id", institutionId)
      .order("name"),

    courses: supabase
      .from("courses")
      .select("*,department:departments(id,name,code)")
      .eq("institution_id", institutionId)
      .order("code"),

    curriculum: supabase
      .from("programme_courses")
      .select("*,programme:programmes(id,name,code),course:courses(id,name,code,credit_hours)")
      .eq("institution_id", institutionId)
      .order("level_number")
      .order("period_number"),

    offerings: supabase
      .from("course_offerings")
      .select(`
        *,
        course:courses(id,code,name,credit_hours),
        academic_year:academic_years(id,name),
        academic_period:academic_periods(id,name,period_number),
        department:departments(id,name,code),
        programme:programmes(id,name,code)
      `)
      .eq("institution_id", institutionId)
      .order("created_at", { ascending: false }),

    lecturers: supabase
      .from("course_lecturers")
      .select(`
        *,
        course_offering:course_offerings(
          id,section_code,level_number,
          course:courses(id,code,name),
          academic_period:academic_periods(id,name)
        ),
        lecturer_profile:lecturer_profiles(
          id,academic_rank,specialization,is_active,
          staff:staff(id,staff_number,first_name,middle_name,last_name,email,job_title,employment_status)
        )
      `)
      .eq("institution_id", institutionId)
      .order("assigned_at", { ascending: false }),

    schedules: supabase
      .from("course_schedules")
      .select(`
        *,
        course_offering:course_offerings(
          id,section_code,level_number,
          course:courses(id,code,name),
          academic_period:academic_periods(id,name)
        )
      `)
      .eq("institution_id", institutionId)
      .order("day_of_week")
      .order("start_time"),

    lecturerProfiles: supabase
      .from("lecturer_profiles")
      .select(`
        id,staff_id,academic_rank,specialization,is_active,
        staff:staff(id,staff_number,first_name,middle_name,last_name,email,job_title,employment_status)
      `)
      .eq("institution_id", institutionId)
      .eq("is_active", true)
      .order("created_at"),
  };

  const keys = Object.keys(queries);
  const results = await Promise.all(Object.values(queries));
  const firstError = results.find((result) => result.error)?.error;

  if (firstError) return { data: null, error: firstError };

  return {
    data: Object.fromEntries(
      keys.map((key, index) => [key, results[index].data || []])
    ),
    error: null,
  };
}

export async function saveAcademicRecord(entity, institutionId, payload, id = null) {
  const table = TABLES[entity];
  if (!table) return { data: null, error: new Error("Unknown academic entity.") };

  const values = { ...payload, institution_id: institutionId };

  if (id) {
    const update = { ...values };
    if (entity !== "lecturers") update.updated_at = new Date().toISOString();

    return supabase
      .from(table)
      .update(update)
      .eq("id", id)
      .select()
      .single();
  }

  return supabase.from(table).insert(values).select().single();
}

export async function setAcademicRecordStatus(entity, id, status) {
  const table = TABLES[entity];

  if (!table || ["curriculum", "lecturers", "schedules"].includes(entity)) {
    return { error: new Error("Status is not supported for this record.") };
  }

  return supabase
    .from(table)
    .update({ status, updated_at: new Date().toISOString() })
    .eq("id", id);
}

export async function setCurrentAcademicYear(institutionId, id) {
  const clear = await supabase
    .from("academic_years")
    .update({ is_current: false, updated_at: new Date().toISOString() })
    .eq("institution_id", institutionId);

  if (clear.error) return clear;

  return supabase
    .from("academic_years")
    .update({
      is_current: true,
      status: "active",
      updated_at: new Date().toISOString(),
    })
    .eq("id", id);
}

export async function setCurrentAcademicPeriod(institutionId, academicYearId, id) {
  const clear = await supabase
    .from("academic_periods")
    .update({ is_current: false, updated_at: new Date().toISOString() })
    .eq("institution_id", institutionId)
    .eq("academic_year_id", academicYearId);

  if (clear.error) return clear;

  return supabase
    .from("academic_periods")
    .update({
      is_current: true,
      status: "active",
      updated_at: new Date().toISOString(),
    })
    .eq("id", id);
}


export async function bulkAssignLecturer({
  institutionId,
  lecturerProfileId,
  courseOfferingIds,
  allocationRole = "lecturer",
  workloadPercentage = 100,
  makePrimary = false,
}) {
  if (!institutionId || !lecturerProfileId || !courseOfferingIds?.length) {
    return {
      data: null,
      error: new Error("Lecturer and at least one course offering are required."),
    };
  }

  const rows = courseOfferingIds.map((courseOfferingId) => ({
    institution_id: institutionId,
    course_offering_id: courseOfferingId,
    lecturer_profile_id: lecturerProfileId,
    allocation_role: allocationRole,
    workload_percentage: Number(workloadPercentage || 100),
    is_primary: Boolean(makePrimary),
  }));

  // Do not overwrite an existing lecturer/course allocation accidentally.
  const { data: existing, error: existingError } = await supabase
    .from("course_lecturers")
    .select("id,course_offering_id,lecturer_profile_id")
    .eq("institution_id", institutionId)
    .eq("lecturer_profile_id", lecturerProfileId)
    .in("course_offering_id", courseOfferingIds);

  if (existingError) return { data: null, error: existingError };

  const existingOfferingIds = new Set(
    (existing || []).map((row) => row.course_offering_id)
  );

  const inserts = rows.filter(
    (row) => !existingOfferingIds.has(row.course_offering_id)
  );

  if (!inserts.length) {
    return {
      data: {
        inserted: 0,
        skipped: courseOfferingIds.length,
      },
      error: null,
    };
  }

  // If these are primary allocations, clear existing primary flags on the
  // selected offerings first. This still permits co-lecturers/tutors.
  if (makePrimary) {
    const clearPrimary = await supabase
      .from("course_lecturers")
      .update({ is_primary: false })
      .eq("institution_id", institutionId)
      .in("course_offering_id", inserts.map((row) => row.course_offering_id));

    if (clearPrimary.error) return { data: null, error: clearPrimary.error };
  }

  const { data, error } = await supabase
    .from("course_lecturers")
    .insert(inserts)
    .select();

  if (error) return { data: null, error };

  return {
    data: {
      rows: data || [],
      inserted: data?.length || 0,
      skipped: courseOfferingIds.length - inserts.length,
    },
    error: null,
  };
}

export async function removeLecturerAllocation(id) {
  return supabase
    .from("course_lecturers")
    .delete()
    .eq("id", id);
}
