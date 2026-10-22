import { supabase } from "../lib/supabase";

const DOCUMENT_BUCKET = "admission-documents";

export async function loadAdmissionsPhase1(institutionId) {
  const [
    cycles,
    applicants,
    applications,
    programmes,
    years,
    qualifications,
    documents,
    payments,
    feeRules,
    documentRequirements,
    subjectResults,
    eligibilityRules,
    reviews,
    offers,
  ] = await Promise.all([
    supabase
      .from("admission_cycles")
      .select("*,academic_year:academic_years(id,name)")
      .eq("institution_id", institutionId)
      .order("created_at", { ascending: false }),

    supabase
      .from("applicants")
      .select("*")
      .eq("institution_id", institutionId)
      .order("created_at", { ascending: false }),

    supabase
      .from("applications")
      .select(`
        *,
        admission_cycle:admission_cycles(
          id,name,application_prefix,status,settings,
          admission_level,applicant_scope,max_programme_choices,
          payment_required,allow_draft_before_payment
        ),
        applicant:applicants(id,first_name,middle_name,last_name,email,phone,applicant_category),
        choices:application_choices(
          id,choice_order,status,
          programme:programmes(id,name,code,award_type)
        )
      `)
      .eq("institution_id", institutionId)
      .order("created_at", { ascending: false }),

    supabase
      .from("programmes")
      .select("id,name,code,award_type,status")
      .eq("institution_id", institutionId)
      .eq("status", "active")
      .order("name"),

    supabase
      .from("academic_years")
      .select("id,name,is_current,status,start_date,end_date")
      .eq("institution_id", institutionId)
      .order("start_date", { ascending: false }),

    supabase
      .from("applicant_qualifications")
      .select("*")
      .eq("institution_id", institutionId)
      .order("created_at", { ascending: false }),

    supabase
      .from("application_documents")
      .select("*")
      .eq("institution_id", institutionId)
      .order("created_at", { ascending: false }),

    supabase
      .from("admission_application_payments")
      .select("*")
      .eq("institution_id", institutionId)
      .order("created_at", { ascending: false }),

    supabase
      .from("admission_fee_rules")
      .select("*,programme:programmes(id,name,code)")
      .eq("institution_id", institutionId)
      .order("created_at", { ascending: false }),

    supabase
      .from("admission_document_requirements")
      .select("*,programme:programmes(id,name,code)")
      .eq("institution_id", institutionId)
      .order("sequence_no", { ascending: true }),

    supabase
      .from("applicant_subject_results")
      .select("*")
      .eq("institution_id", institutionId)
      .order("created_at", { ascending: true }),

    supabase
      .from("programme_admission_rules")
      .select(`
        *,
        programme:programmes(id,name,code),
        admission_cycle:admission_cycles(id,name),
        subjects:programme_admission_subject_rules(*)
      `)
      .eq("institution_id", institutionId)
      .order("created_at", { ascending: false }),

    supabase
      .from("application_reviews")
      .select("*")
      .eq("institution_id", institutionId)
      .order("created_at", { ascending: false }),

    supabase
      .from("admission_offers")
      .select("*,programme:programmes(id,name,code)")
      .eq("institution_id", institutionId)
      .order("created_at", { ascending: false }),
  ]);

  const results = {
    cycles,
    applicants,
    applications,
    programmes,
    years,
    qualifications,
    documents,
    payments,
    feeRules,
    documentRequirements,
    subjectResults,
    eligibilityRules,
    reviews,
    offers,
  };

  const firstError = Object.values(results).find((result) => result.error)?.error;

  if (firstError) return { data: null, error: firstError };

  return {
    data: {
      cycles: cycles.data || [],
      applicants: applicants.data || [],
      applications: applications.data || [],
      programmes: programmes.data || [],
      years: years.data || [],
      qualifications: qualifications.data || [],
      documents: documents.data || [],
      payments: payments.data || [],
      feeRules: feeRules.data || [],
      documentRequirements: documentRequirements.data || [],
      subjectResults: subjectResults.data || [],
      eligibilityRules: eligibilityRules.data || [],
      reviews: reviews.data || [],
      offers: offers.data || [],
    },
    error: null,
  };
}

export function saveAdmissionCycle(institutionId, values, id = null) {
  const legacyAmount = Number(values.application_fee || 0);

  const payload = {
    institution_id: institutionId,
    academic_year_id: values.academic_year_id,
    name: values.name.trim(),
    application_prefix: (values.application_prefix || "APP").trim().toUpperCase(),
    opens_at: values.opens_at || null,
    closes_at: values.closes_at || null,
    admission_level: values.admission_level || "undergraduate",
    applicant_scope: values.applicant_scope || "both",
    max_programme_choices: Number(values.max_programme_choices || 3),
    payment_required: Boolean(values.payment_required),
    allow_draft_before_payment: Boolean(values.allow_draft_before_payment),
    application_instructions: values.application_instructions?.trim() || null,

    // Temporary compatibility mirror for the existing Paystack Edge Function.
    // Phase 2 fee rules are the source of truth for new configuration.
    settings: {
      ...(values.settings || {}),
      application_fee: Number.isFinite(legacyAmount) ? legacyAmount : 0,
      currency: (values.currency || "GHS").toUpperCase(),
    },
  };

  if (id) {
    return supabase
      .from("admission_cycles")
      .update({ ...payload, updated_at: new Date().toISOString() })
      .eq("id", id)
      .select("*,academic_year:academic_years(id,name)")
      .single();
  }

  return supabase
    .from("admission_cycles")
    .insert(payload)
    .select("*,academic_year:academic_years(id,name)")
    .single();
}

export function saveAdmissionFeeRule(institutionId, values, id = null) {
  const payload = {
    institution_id: institutionId,
    admission_cycle_id: values.admission_cycle_id,
    programme_id: values.programme_id || null,
    applicant_category: values.applicant_category,
    admission_level: values.admission_level,
    amount: Number(values.amount || 0),
    currency_code: (values.currency_code || "GHS").toUpperCase(),
    is_active: values.is_active !== false,
  };

  if (id) {
    return supabase
      .from("admission_fee_rules")
      .update({ ...payload, updated_at: new Date().toISOString() })
      .eq("id", id)
      .select()
      .single();
  }
  return supabase.from("admission_fee_rules").insert(payload).select().single();
}

export function saveAdmissionDocumentRequirement(institutionId, values, id = null) {
  const payload = {
    institution_id: institutionId,
    admission_cycle_id: values.admission_cycle_id,
    programme_id: values.programme_id || null,
    applicant_category: values.applicant_category || "both",
    admission_level: values.admission_level || "both",
    document_type: values.document_type.trim().toLowerCase().replace(/[^a-z0-9]+/g, "_"),
    display_name: values.display_name.trim(),
    description: values.description?.trim() || null,
    is_required: values.is_required !== false,
    requires_verification: values.requires_verification !== false,
    sequence_no: Number(values.sequence_no || 100),
    is_active: values.is_active !== false,
  };

  if (id) {
    return supabase
      .from("admission_document_requirements")
      .update({ ...payload, updated_at: new Date().toISOString() })
      .eq("id", id)
      .select()
      .single();
  }
  return supabase
    .from("admission_document_requirements")
    .insert(payload)
    .select()
    .single();
}

export function saveApplicant(institutionId, values, id = null) {
  const payload = {
    institution_id: institutionId,
    first_name: values.first_name.trim(),
    middle_name: values.middle_name?.trim() || null,
    last_name: values.last_name.trim(),
    date_of_birth: values.date_of_birth || null,
    gender: values.gender || null,
    email: values.email?.trim().toLowerCase() || null,
    phone: values.phone?.trim() || null,
    nationality: values.nationality?.trim() || "Ghanaian",
    country_of_residence: values.country_of_residence?.trim() || "Ghana",
    address: values.address?.trim() || null,
    city: values.city?.trim() || null,
    region: values.region?.trim() || null,
    emergency_contact_name: values.emergency_contact_name?.trim() || null,
    emergency_contact_phone: values.emergency_contact_phone?.trim() || null,
  };

  if (id) {
    return supabase
      .from("applicants")
      .update({ ...payload, updated_at: new Date().toISOString() })
      .eq("id", id)
      .select()
      .single();
  }

  return supabase.from("applicants").insert(payload).select().single();
}

export function createAdmissionApplication({
  institutionId,
  admissionCycleId,
  applicantId,
  entryType = "regular",
  firstProgrammeId,
  secondProgrammeId = null,
  notes = null,
}) {
  return supabase.rpc("create_internal_admission_application", {
    p_institution_id: institutionId,
    p_admission_cycle_id: admissionCycleId,
    p_applicant_id: applicantId,
    p_entry_type: entryType,
    p_first_programme_id: firstProgrammeId,
    p_second_programme_id: secondProgrammeId || null,
    p_notes: notes || null,
  });
}

export function saveApplicantQualification(
  institutionId,
  applicantId,
  values,
  id = null
) {
  const payload = {
    institution_id: institutionId,
    applicant_id: applicantId,
    qualification_type: values.qualification_type.trim(),
    institution_name: values.institution_name?.trim() || null,
    examining_body: values.examining_body?.trim() || null,
    index_number: values.index_number?.trim() || null,
    completion_year: values.completion_year
      ? Number(values.completion_year)
      : null,
    overall_result: values.overall_result?.trim() || null,
    details: values.details || {},
  };

  if (id) {
    return supabase
      .from("applicant_qualifications")
      .update({ ...payload, updated_at: new Date().toISOString() })
      .eq("id", id)
      .select()
      .single();
  }

  return supabase
    .from("applicant_qualifications")
    .insert(payload)
    .select()
    .single();
}

export async function uploadApplicationDocument({
  institutionId,
  applicationId,
  documentType,
  file,
}) {
  if (!file) {
    return { data: null, error: new Error("Choose a file to upload.") };
  }

  const safeName = file.name
    .replace(/[^a-zA-Z0-9._-]+/g, "-")
    .replace(/-+/g, "-");

  const path = `${institutionId}/${applicationId}/${crypto.randomUUID()}-${safeName}`;

  const upload = await supabase.storage
    .from(DOCUMENT_BUCKET)
    .upload(path, file, {
      cacheControl: "3600",
      upsert: false,
      contentType: file.type || undefined,
    });

  if (upload.error) {
    return { data: null, error: upload.error };
  }

  const insert = await supabase
    .from("application_documents")
    .insert({
      institution_id: institutionId,
      application_id: applicationId,
      document_type: documentType.trim(),
      file_name: file.name,
      storage_path: path,
      mime_type: file.type || null,
      file_size_bytes: file.size || null,
      verification_status: "pending",
    })
    .select()
    .single();

  if (insert.error) {
    await supabase.storage.from(DOCUMENT_BUCKET).remove([path]);
    return { data: null, error: insert.error };
  }

  return insert;
}

export async function downloadApplicationDocument(storagePath, fileName = "document") {
  const result = await supabase.storage
    .from(DOCUMENT_BUCKET)
    .download(storagePath);

  if (result.error) return result;

  const url = URL.createObjectURL(result.data);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = fileName;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);

  return { data: true, error: null };
}

export function reviewApplicationDocument(documentId, status, notes = null) {
  return supabase.rpc("review_application_document", {
    p_document_id: documentId,
    p_status: status,
    p_notes: notes || null,
  });
}

export function completeApplicationReview(applicationId, notes = null) {
  return supabase.rpc("complete_internal_application_review", {
    p_application_id: applicationId,
    p_notes: notes || null,
  });
}


export function recordOfflineApplicationPayment({
  applicationId,
  amount,
  currency = "GHS",
  paymentMethod,
  provider = null,
  providerReference = null,
  paidAt = null,
  notes = null,
}) {
  return supabase.rpc("record_offline_admission_payment", {
    p_application_id: applicationId,
    p_amount: Number(amount),
    p_currency: currency,
    p_payment_method: paymentMethod,
    p_provider: provider || null,
    p_provider_reference: providerReference || null,
    p_paid_at: paidAt || null,
    p_notes: notes || null,
  });
}

export function verifyOfflineApplicationPayment(paymentId) {
  return supabase.rpc("verify_offline_admission_payment", {
    p_payment_id: paymentId,
  });
}

export function submitAdmissionApplication(applicationId) {
  return supabase.rpc("submit_admission_application", {
    p_application_id: applicationId,
  });
}

export async function initializePaystackAdmissionPayment(applicationId) {
  const { data, error } = await supabase.functions.invoke(
    "initialize-admission-payment",
    {
      body: {
        application_id: applicationId,
        callback_url: `${window.location.origin}/admin/admissions?payment=callback`,
      },
    }
  );

  if (!error && data?.ok === false) {
    return { data: null, error: new Error(data.error) };
  }

  return { data, error };
}

export async function verifyPaystackAdmissionPayment(reference) {
  const { data, error } = await supabase.functions.invoke(
    "verify-admission-payment",
    {
      body: { reference },
    }
  );

  if (!error && data?.ok === false) {
    return { data: null, error: new Error(data.error) };
  }

  return { data, error };
}


export function saveProgrammeAdmissionRule(institutionId, values) {
  const subjectRules = (values.subject_rules || [])
    .filter((row) => row.subject_name?.trim())
    .map((row) => ({
      subject_name: row.subject_name.trim(),
      subject_group: row.subject_group || "required",
      max_grade_rank: Number(row.max_grade_rank || values.default_max_grade_rank || 6),
    }));

  return supabase.rpc("unimis_save_programme_admission_rule", {
    p_institution_id: institutionId,
    p_programme_id: values.programme_id,
    p_admission_cycle_id: values.admission_cycle_id || null,
    p_qualification_type: values.qualification_type || "WASSCE",
    p_max_aggregate: values.max_aggregate === "" || values.max_aggregate == null
      ? null
      : Number(values.max_aggregate),
    p_minimum_elective_passes: Number(values.minimum_elective_passes || 0),
    p_default_max_grade_rank: Number(values.default_max_grade_rank || 6),
    p_notes: values.notes?.trim() || null,
    p_subject_rules: subjectRules,
    p_rule_id: values.id || null,
  });
}

export function evaluateApplicationEligibility(applicationId) {
  return supabase.rpc("unimis_evaluate_application_eligibility", {
    p_application_id: applicationId,
  });
}

export function verifyApplicantQualification(
  qualificationId,
  status,
  source = "manual",
  reference = null,
  notes = null
) {
  return supabase.rpc("unimis_verify_applicant_qualification", {
    p_qualification_id: qualificationId,
    p_status: status,
    p_source: source,
    p_reference: reference || null,
    p_notes: notes || null,
  });
}

export function loadAdmissionsEligibilityRegister(institutionId, admissionCycleId = null) {
  return supabase.rpc("unimis_admissions_eligibility_register", {
    p_institution_id: institutionId,
    p_admission_cycle_id: admissionCycleId || null,
  });
}


export function recordWaecVerification({
  qualificationId,
  status,
  method = "waec_portal",
  reference = null,
  notes = null,
  officialResult = null,
  comparisonResult = null,
}) {
  return supabase.rpc("unimis_record_waec_verification", {
    p_qualification_id: qualificationId,
    p_status: status,
    p_method: method,
    p_reference: reference || null,
    p_notes: notes || null,
    p_official_result: officialResult || null,
    p_comparison_result: comparisonResult || null,
  });
}

export function loadWaecVerificationEvents(institutionId) {
  return supabase
    .from("waec_verification_events")
    .select("*")
    .eq("institution_id", institutionId)
    .order("created_at", { ascending: false });
}


export function submitAdmissionRecommendation({
  applicationId,
  programmeId,
  recommendation,
  comments = null,
}) {
  return supabase.rpc("unimis_submit_admission_recommendation", {
    p_application_id: applicationId,
    p_programme_id: programmeId || null,
    p_recommendation: recommendation,
    p_comments: comments || null,
  });
}

export function approveAdmissionRecommendation({
  applicationId,
  action,
  programmeId = null,
  comments = null,
  conditions = null,
  expiresAt = null,
}) {
  return supabase.rpc("unimis_approve_admission_recommendation", {
    p_application_id: applicationId,
    p_action: action,
    p_programme_id: programmeId || null,
    p_comments: comments || null,
    p_conditions: conditions || null,
    p_expires_at: expiresAt || null,
  });
}

export async function loadWaecBatches(institutionId){return supabase.from("waec_verification_batches").select("*").eq("institution_id",institutionId).order("created_at",{ascending:false});}
export async function loadWaecBatchCandidates(institutionId){return supabase.from("waec_verification_batch_candidates").select("*").eq("institution_id",institutionId).order("created_at",{ascending:false});}
export function createWaecBatch({qualificationIds,admissionCycleId=null,notes=null}){return supabase.rpc("unimis_create_waec_verification_batch",{p_qualification_ids:qualificationIds,p_admission_cycle_id:admissionCycleId||null,p_notes:notes||null});}
export function updateWaecBatchStatus({batchId,status,providerReference=null,notes=null}){return supabase.rpc("unimis_update_waec_batch_status",{p_batch_id:batchId,p_status:status,p_provider_reference:providerReference||null,p_notes:notes||null});}
export function reconcileWaecBulkBatch({batchId,rows}){return supabase.rpc("unimis_reconcile_waec_bulk_batch",{p_batch_id:batchId,p_rows:rows});}
