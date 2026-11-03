import {printLegacyDocument122} from "../../lib/printInPlace098";
import Toast from "../../components/Toast";
import {useConfirm} from "../../contexts/ConfirmContext";
import WaecVerificationWorkspaceV2 from "./WaecVerificationWorkspaceV2";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  CalendarDays,
  FileText,
  GraduationCap,
  LayoutDashboard,
  Pencil,
  Plus,
  RefreshCw,
  Search,
  UserRound,
  Users,
  X,
  Upload,
  BadgeCheck,
  BadgeX,
  ClipboardCheck,
  Download,
  BookMarked,
  CreditCard,
  Banknote,
  Send,
  CheckCircle2,
  ExternalLink,
  ListChecks,
  BarChart3,
  FileSpreadsheet,
  Printer,
  ShieldCheck,
} from "lucide-react";
import { useUserContext } from "../../contexts/UserContext";
import DashboardSectionMenu from "../../components/navigation/DashboardSectionMenu";
import {
  createAdmissionApplication,
  loadAdmissionsPhase1,
  saveAdmissionCycle,
  saveApplicant,
  saveApplicantQualification,
  uploadApplicationDocument,
  downloadApplicationDocument,
  reviewApplicationDocument,
  completeApplicationReview,
  recordOfflineApplicationPayment,
  verifyOfflineApplicationPayment,
  submitAdmissionApplication,
  initializePaystackAdmissionPayment,
  verifyPaystackAdmissionPayment,
  saveAdmissionFeeRule,
  saveAdmissionDocumentRequirement,
  saveProgrammeAdmissionRule,
  evaluateApplicationEligibility,
  verifyApplicantQualification,
  loadAdmissionsEligibilityRegister,
  recordWaecVerification,
  submitAdmissionRecommendation,
  approveAdmissionRecommendation,
} from "../../services/admissions";

const TABS = [
  ["overview", "Dashboard", LayoutDashboard],
  ["cycles", "Admission Cycles", CalendarDays],
  ["configuration", "Fees & Requirements", CreditCard],
  ["eligibility", "Eligibility Rules", GraduationCap],
  ["applicants", "Applicants", Users],
  ["applications", "Applications", FileText],
  ["payment", "Application Completion", CreditCard],
  ["records", "Qualifications & Documents", BookMarked],
  ["verification", "Verification Queue", ListChecks],
  ["waec-verification", "WAEC Verification", ShieldCheck],
  ["eligibility-register", "Eligibility Register", GraduationCap],
  ["review", "Review & Recommendation", ClipboardCheck],
  ["approval", "Approval & Offers", BadgeCheck],
  ["reports", "Admissions Reports", BarChart3],
];

const ADMISSIONS_MENU_GROUPS = [
  { label: "Overview", items: TABS.filter(([key]) => key === "overview").map(([key, label, icon]) => ({ key, label, icon })) },
  { label: "Setup", items: TABS.filter(([key]) => ["cycles", "configuration", "eligibility"].includes(key)).map(([key, label, icon]) => ({ key, label, icon })) },
  { label: "Applications", items: TABS.filter(([key]) => ["applicants", "applications", "payment"].includes(key)).map(([key, label, icon]) => ({ key, label, icon })) },
  { label: "Processing — Submitted Applications", items: TABS.filter(([key]) => ["records", "verification", "waec-verification", "eligibility-register", "review", "approval"].includes(key)).map(([key, label, icon]) => ({ key, label, icon })) },
  { label: "Reports & Analytics", items: TABS.filter(([key]) => key === "reports").map(([key, label, icon]) => ({ key, label: "Admissions Reports", icon, subitem: true })) },
];

const EMPTY_CYCLE = {
  academic_year_id: "",
  name: "",
  application_prefix: "APP",
  opens_at: "",
  closes_at: "",
  admission_level: "undergraduate",
  applicant_scope: "both",
  max_programme_choices: 3,
  payment_required: true,
  allow_draft_before_payment: true,
  application_instructions: "",
  application_fee: 0,
  currency: "GHS",
};

const EMPTY_APPLICANT = {
  first_name: "",
  middle_name: "",
  last_name: "",
  date_of_birth: "",
  gender: "",
  email: "",
  phone: "",
  nationality: "Ghanaian",
  country_of_residence: "Ghana",
  address: "",
  city: "",
  region: "",
  emergency_contact_name: "",
  emergency_contact_phone: "",
};

const EMPTY_APPLICATION = {
  admission_cycle_id: "",
  applicant_id: "",
  entry_type: "regular",
  first_programme_id: "",
  second_programme_id: "",
  notes: "",
};

function isProcessingReady(application) {
  if (!application?.submitted_at) return false;
  const payment = String(application.payment_status || "").toLowerCase();
  const paymentRequired = application.admission_cycle?.payment_required !== false;
  if (!paymentRequired) return true;
  return ["paid", "verified", "not_required"].includes(payment);
}

function applicantName(applicant) {
  if (!applicant) return "Unknown applicant";
  return [applicant.first_name, applicant.middle_name, applicant.last_name]
    .filter(Boolean)
    .join(" ");
}

function choiceProgramme(application, order) {
  return application.choices
    ?.find((choice) => Number(choice.choice_order) === order)
    ?.programme;
}

function resolveApplicationFee(application, feeRules = [], payments = []) {
  if (!application) return { amount: 0, currency: "GHS", source: "none" };

  const verified = payments.find(
    (row) => row.application_id === application.id && row.status === "verified"
  );
  if (verified) {
    return {
      amount: Number(verified.amount || 0),
      currency: verified.currency || "GHS",
      source: "verified-payment",
    };
  }

  const category = application.applicant?.applicant_category || null;
  const level = application.admission_cycle?.admission_level || null;
  const programmeIds = (application.choices || [])
    .map((choice) => choice.programme?.id)
    .filter(Boolean);

  const candidates = feeRules.filter((rule) => {
    if (rule.is_active === false) return false;
    if (rule.admission_cycle_id !== application.admission_cycle_id) return false;
    if (category && rule.applicant_category && rule.applicant_category !== category) return false;
    if (level && rule.admission_level && rule.admission_level !== level) return false;
    if (rule.programme_id && !programmeIds.includes(rule.programme_id)) return false;
    return true;
  });

  const rule = candidates.find((row) => row.programme_id) || candidates.find((row) => !row.programme_id);
  if (rule) {
    return {
      amount: Number(rule.amount || 0),
      currency: rule.currency_code || "GHS",
      source: "fee-rule",
    };
  }

  return {
    amount: Number(application.admission_cycle?.settings?.application_fee || 0),
    currency: application.admission_cycle?.settings?.currency || "GHS",
    source: "legacy",
  };
}

function paymentMethodLabel(payment) {
  const providerChannel = payment?.metadata?.paystack_verification?.channel;
  const raw = providerChannel || payment?.payment_method || payment?.channel || "unknown";
  return String(raw).replaceAll("_", " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function paymentGroupLabel(payment) {
  const side = payment?.channel === "offline" ? "Offline" : "Online";
  return `${side} • ${paymentMethodLabel(payment)}`;
}

function escapeHtml(value = "") {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}


export default function AdmissionsManagement() {
  const { institutionId } = useUserContext();
  const confirmAction = useConfirm();

  const [activeTab, setActiveTab] = useState("overview");
  const [data, setData] = useState({
    cycles: [],
    applicants: [],
    applications: [],
    programmes: [],
    years: [],
    qualifications: [],
    documents: [],
    payments: [],
    feeRules: [],
    documentRequirements: [],
    subjectResults: [],
    eligibilityRules: [],
  });
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [query, setQuery] = useState("");
  const [modal, setModal] = useState(null);
  const [form, setForm] = useState({});
  const [selectedApplicationId, setSelectedApplicationId] = useState("");
  const [selectedApplicantId, setSelectedApplicantId] = useState("");
  const [reviewNotes, setReviewNotes] = useState("");
  const [documentNotes, setDocumentNotes] = useState({});
  const [offlinePayment, setOfflinePayment] = useState({
    amount: "",
    currency: "GHS",
    payment_method: "cash",
    provider: "",
    provider_reference: "",
    paid_at: "",
    notes: "",
  });

  const load = useCallback(async () => {
    if (!institutionId) {
      setLoading(false);
      return;
    }

    setLoading(true);
    setError("");

    const result = await loadAdmissionsPhase1(institutionId);

    if (result.error) setError(result.error.message);
    else setData(result.data);

    setLoading(false);
  }, [institutionId]);

  useEffect(() => {
    load();
  }, [load]);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const reference = params.get("reference");

    if (params.get("payment") === "callback" && reference) {
      handleVerifyPaystack(reference).finally(() => {
        const url = new URL(window.location.href);
        url.searchParams.delete("payment");
        url.searchParams.delete("reference");
        window.history.replaceState({}, "", url.toString());
      });
    }
  }, []);

  const stats = useMemo(() => {
    const statuses = data.applications.reduce((acc, row) => {
      acc[row.status] = (acc[row.status] || 0) + 1;
      return acc;
    }, {});

    return {
      applicants: data.applicants.length,
      applications: data.applications.length,
      submitted: statuses.submitted || 0,
      review:
        (statuses.under_review || 0) +
        (statuses.reviewing || 0) +
        (statuses.reviewed || 0),
    };
  }, [data]);

  const filteredCycles = useMemo(() => {
    const q = query.toLowerCase().trim();
    if (!q) return data.cycles;
    return data.cycles.filter((row) =>
      [row.name, row.application_prefix, row.status, row.academic_year?.name]
        .filter(Boolean)
        .join(" ")
        .toLowerCase()
        .includes(q)
    );
  }, [data.cycles, query]);

  const filteredApplicants = useMemo(() => {
    const q = query.toLowerCase().trim();
    if (!q) return data.applicants;
    return data.applicants.filter((row) =>
      [
        row.first_name,
        row.middle_name,
        row.last_name,
        row.email,
        row.phone,
        row.region,
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase()
        .includes(q)
    );
  }, [data.applicants, query]);

  const filteredApplications = useMemo(() => {
    const q = query.toLowerCase().trim();
    if (!q) return data.applications;
    return data.applications.filter((row) =>
      [
        row.application_number,
        row.entry_type,
        row.status,
        applicantName(row.applicant),
        row.applicant?.email,
        row.admission_cycle?.name,
        choiceProgramme(row, 1)?.name,
        choiceProgramme(row, 1)?.code,
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase()
        .includes(q)
    );
  }, [data.applications, query]);

  function openCycle(row = null) {
    setModal({ type: "cycle", id: row?.id || null });
    setForm(
      row
        ? {
            academic_year_id: row.academic_year_id || "",
            name: row.name || "",
            application_prefix: row.application_prefix || "APP",
            opens_at: row.opens_at ? String(row.opens_at).slice(0, 16) : "",
            closes_at: row.closes_at ? String(row.closes_at).slice(0, 16) : "",
            admission_level: row.admission_level || "undergraduate",
            applicant_scope: row.applicant_scope || "both",
            max_programme_choices: row.max_programme_choices || 3,
            payment_required: row.payment_required !== false,
            allow_draft_before_payment: row.allow_draft_before_payment !== false,
            application_instructions: row.application_instructions || "",
            application_fee: row.settings?.application_fee ?? 0,
            currency: row.settings?.currency || "GHS",
            settings: row.settings || {},
          }
        : { ...EMPTY_CYCLE }
    );
    setError("");
    setMessage("");
  }

  function openFeeRule(row = null) {
    setModal({ type: "feeRule", id: row?.id || null });
    setForm(row ? {
      admission_cycle_id: row.admission_cycle_id || "",
      programme_id: row.programme_id || "",
      applicant_category: row.applicant_category || "local",
      admission_level: row.admission_level || "undergraduate",
      amount: row.amount ?? 0,
      currency_code: row.currency_code || "GHS",
      is_active: row.is_active !== false,
    } : {
      admission_cycle_id: data.cycles[0]?.id || "",
      programme_id: "",
      applicant_category: "local",
      admission_level: "undergraduate",
      amount: 0,
      currency_code: "GHS",
      is_active: true,
    });
    setError(""); setMessage("");
  }

  function openRequirement(row = null) {
    setModal({ type: "requirement", id: row?.id || null });
    setForm(row ? {
      admission_cycle_id: row.admission_cycle_id || "",
      programme_id: row.programme_id || "",
      applicant_category: row.applicant_category || "both",
      admission_level: row.admission_level || "both",
      document_type: row.document_type || "",
      display_name: row.display_name || "",
      description: row.description || "",
      is_required: row.is_required !== false,
      requires_verification: row.requires_verification !== false,
      sequence_no: row.sequence_no || 100,
      is_active: row.is_active !== false,
    } : {
      admission_cycle_id: data.cycles[0]?.id || "",
      programme_id: "",
      applicant_category: "both",
      admission_level: "both",
      document_type: "",
      display_name: "",
      description: "",
      is_required: true,
      requires_verification: true,
      sequence_no: 100,
      is_active: true,
    });
    setError(""); setMessage("");
  }

  function openApplicant(row = null) {
    setModal({ type: "applicant", id: row?.id || null });
    setForm(
      row
        ? Object.fromEntries(
            Object.keys(EMPTY_APPLICANT).map((key) => [
              key,
              row[key] ?? EMPTY_APPLICANT[key],
            ])
          )
        : { ...EMPTY_APPLICANT }
    );
    setError("");
    setMessage("");
  }

  function openApplication() {
    const currentYear = data.years.find((row) => row.is_current);
    const preferredCycle =
      data.cycles.find(
        (row) => row.academic_year_id === currentYear?.id
      ) || data.cycles[0];

    setModal({ type: "application", id: null });
    setForm({
      ...EMPTY_APPLICATION,
      admission_cycle_id: preferredCycle?.id || "",
    });
    setError("");
    setMessage("");
  }


  function openQualification(row = null) {
    const applicantId =
      selectedApplicantId ||
      data.applications.find((application) => application.id === selectedApplicationId)
        ?.applicant_id ||
      "";

    if (!applicantId) {
      setError("Select an applicant/application first.");
      return;
    }

    setModal({ type: "qualification", id: row?.id || null });
    setForm(
      row
        ? {
            qualification_type: row.qualification_type || "",
            institution_name: row.institution_name || "",
            examining_body: row.examining_body || "",
            index_number: row.index_number || "",
            completion_year: row.completion_year || "",
            overall_result: row.overall_result || "",
          }
        : {
            qualification_type: "",
            institution_name: "",
            examining_body: "",
            index_number: "",
            completion_year: "",
            overall_result: "",
          }
    );
    setSelectedApplicantId(applicantId);
    setError("");
    setMessage("");
  }

  function openDocumentUpload() {
    if (!selectedApplicationId) {
      setError("Select an application first.");
      return;
    }

    setModal({ type: "document", id: null });
    setForm({
      document_type: "",
      file: null,
    });
    setError("");
    setMessage("");
  }

  async function handleDocumentReview(documentId, status) {
    setBusy(`doc-${documentId}`);
    setError("");
    setMessage("");

    const result = await reviewApplicationDocument(
      documentId,
      status,
      documentNotes[documentId] || null
    );

    if (result.error) {
      setError(result.error.message);
    } else {
      setMessage(`Document marked ${status}.`);
      await load();
    }

    setBusy("");
  }

  async function handleDownload(document) {
    setBusy(`download-${document.id}`);
    setError("");

    const result = await downloadApplicationDocument(
      document.storage_path,
      document.file_name
    );

    if (result.error) setError(result.error.message);

    setBusy("");
  }

  async function handleCompleteReview(applicationId) {
    setBusy(`review-${applicationId}`);
    setError("");
    setMessage("");

    const result = await completeApplicationReview(
      applicationId,
      reviewNotes || null
    );

    if (result.error) {
      setError(result.error.message);
    } else {
      setMessage("Application review completed.");
      setReviewNotes("");
      await load();
    }

    setBusy("");
  }


  async function handleRecordOfflinePayment(application, resolvedFee = null) {
    const fee = Number(resolvedFee?.amount ?? application.admission_cycle?.settings?.application_fee ?? 0);
    const amount = Number(offlinePayment.amount || fee);

    if (!amount || amount <= 0) {
      setError("Enter a valid payment amount.");
      return;
    }

    setBusy("offline-payment");
    setError("");
    setMessage("");

    const result = await recordOfflineApplicationPayment({
      applicationId: application.id,
      amount,
      currency:
        offlinePayment.currency ||
        resolvedFee?.currency ||
        application.admission_cycle?.settings?.currency ||
        "GHS",
      paymentMethod: offlinePayment.payment_method,
      provider: offlinePayment.provider,
      providerReference: offlinePayment.provider_reference,
      paidAt: offlinePayment.paid_at
        ? new Date(offlinePayment.paid_at).toISOString()
        : null,
      notes: offlinePayment.notes,
    });

    if (result.error) {
      setError(result.error.message);
    } else {
      setMessage("Offline payment recorded. Verify it before application submission.");
      setOfflinePayment({
        amount: "",
        currency: "GHS",
        payment_method: "cash",
        provider: "",
        provider_reference: "",
        paid_at: "",
        notes: "",
      });
      await load();
    }

    setBusy("");
  }

  async function handleVerifyOfflinePayment(paymentId) {
    setBusy(`verify-payment-${paymentId}`);
    setError("");
    setMessage("");

    const result = await verifyOfflineApplicationPayment(paymentId);

    if (result.error) setError(result.error.message);
    else {
      setMessage("Offline payment verified.");
      await load();
    }

    setBusy("");
  }

  async function handleOnlinePayment(application) {
    if (!application.applicant?.email) {
      setError("Applicant email is required for Paystack payment.");
      return;
    }

    setBusy("paystack");
    setError("");
    setMessage("");

    const result = await initializePaystackAdmissionPayment(application.id);

    if (result.error) {
      setError(result.error.message);
    } else if (result.data?.authorization_url) {
      window.location.href = result.data.authorization_url;
      return;
    } else {
      setError("Paystack did not return a checkout URL.");
    }

    setBusy("");
  }

  async function handleVerifyPaystack(reference) {
    setBusy("paystack-verify");
    setError("");
    setMessage("");

    const result = await verifyPaystackAdmissionPayment(reference);

    if (result.error) setError(result.error.message);
    else {
      setMessage("Paystack payment verified successfully.");
      await load();
    }

    setBusy("");
  }

  async function handleSubmitApplication(applicationId) {
    setBusy("submit-application");
    setError("");
    setMessage("");

    const result = await submitAdmissionApplication(applicationId);

    if (result.error) setError(result.error.message);
    else {
      setMessage("Application submitted successfully.");
      await load();
    }

    setBusy("");
  }

  async function submit(e) {
    e.preventDefault();
    if (!institutionId || !modal) return;

    setBusy("save");
    setError("");
    setMessage("");

    let result;

    if (modal.type === "cycle") {
      if (form.opens_at && form.closes_at && form.closes_at <= form.opens_at) {
        setError("Admission cycle closing date/time must be after its opening date/time.");
        setBusy("");
        return;
      }

      result = await saveAdmissionCycle(
        institutionId,
        form,
        modal.id
      );
    } else if (modal.type === "feeRule") {
      result = await saveAdmissionFeeRule(institutionId, form, modal.id);
    } else if (modal.type === "requirement") {
      result = await saveAdmissionDocumentRequirement(institutionId, form, modal.id);
    } else if (modal.type === "applicant") {
      result = await saveApplicant(
        institutionId,
        form,
        modal.id
      );
    } else if (modal.type === "qualification") {
      result = await saveApplicantQualification(
        institutionId,
        selectedApplicantId,
        form,
        modal.id
      );
    } else if (modal.type === "document") {
      result = await uploadApplicationDocument({
        institutionId,
        applicationId: selectedApplicationId,
        documentType: form.document_type,
        file: form.file,
      });
    } else {
      if (
        form.second_programme_id &&
        form.second_programme_id === form.first_programme_id
      ) {
        setError("First and second programme choices must be different.");
        setBusy("");
        return;
      }

      result = await createAdmissionApplication({
        institutionId,
        admissionCycleId: form.admission_cycle_id,
        applicantId: form.applicant_id,
        entryType: form.entry_type,
        firstProgrammeId: form.first_programme_id,
        secondProgrammeId: form.second_programme_id,
        notes: form.notes,
      });
    }

    if (result.error) {
      setError(result.error.message);
    } else {
      setMessage(
        modal.type === "cycle"
          ? `Admission cycle ${modal.id ? "updated" : "created"} successfully.`
          : modal.type === "feeRule"
            ? `Application fee rule ${modal.id ? "updated" : "created"} successfully.`
          : modal.type === "requirement"
            ? `Document requirement ${modal.id ? "updated" : "created"} successfully.`
          : modal.type === "applicant"
            ? `Applicant ${modal.id ? "updated" : "created"} successfully.`
            : modal.type === "qualification"
              ? `Qualification ${modal.id ? "updated" : "created"} successfully.`
              : modal.type === "document"
                ? "Document uploaded successfully."
                : "Application created successfully."
      );
      setModal(null);
      await load();
    }

    setBusy("");
  }

  const processingApplications = useMemo(
    () => (data.applications || []).filter(isProcessingReady),
    [data.applications]
  );
  const processingApplicationIds = useMemo(
    () => new Set(processingApplications.map((row) => row.id)),
    [processingApplications]
  );
  const processingApplicantIds = useMemo(
    () => new Set(processingApplications.map((row) => row.applicant_id).filter(Boolean)),
    [processingApplications]
  );
  const processingData = useMemo(() => ({
    ...data,
    applications: processingApplications,
    applicants: (data.applicants || []).filter((row) => processingApplicantIds.has(row.id)),
    qualifications: (data.qualifications || []).filter((row) => processingApplicantIds.has(row.applicant_id)),
    subjectResults: (data.subjectResults || []).filter((row) => processingApplicantIds.has(row.applicant_id)),
    documents: (data.documents || []).filter((row) => processingApplicationIds.has(row.application_id)),
    payments: (data.payments || []).filter((row) => processingApplicationIds.has(row.application_id)),
    reviews: (data.reviews || []).filter((row) => processingApplicationIds.has(row.application_id)),
    offers: (data.offers || []).filter((row) => processingApplicationIds.has(row.application_id)),
  }), [data, processingApplications, processingApplicationIds, processingApplicantIds]);

  return (
    <section>
      <div className="page-heading admissions-heading">
        <div>
          <span className="eyebrow">Admissions Office</span>
          <h1>Admissions Management</h1>
          <p>
            Manage admission cycles, applicant records and programme applications
            using the academic structure already configured in UniMIS.
          </p>
        </div>

        <button type="button" className="secondary-button" onClick={load}>
          <RefreshCw size={17} />
          Refresh
        </button>
      </div>

      <Toast message={error||message} type={error?"error":"success"} onClose={()=>{setError("");setMessage("")}}/>

      <div className="admissions-summary-grid">
        <div><UserRound /><span>Applicants</span><strong>{stats.applicants}</strong></div>
        <div><FileText /><span>Applications</span><strong>{stats.applications}</strong></div>
        <div><GraduationCap /><span>Submitted</span><strong>{stats.submitted}</strong></div>
        <div><Search /><span>Under Review</span><strong>{stats.review}</strong></div>
      </div>
      <div className="processing-gate-note">
        <ShieldCheck size={17}/>
        <span><strong>Processing gate:</strong> formal processing screens contain only applications that have been submitted and whose application fee is satisfied.</span>
        <strong>{processingApplications.length} ready</strong>
      </div>

      <div className="management-card admissions-card">
        <DashboardSectionMenu
          groups={ADMISSIONS_MENU_GROUPS}
          activeKey={activeTab}
          onSelect={(key) => {
            setActiveTab(key);
            setQuery("");
          }}
          className="admissions-section-menu"
        />

        {activeTab === "overview" ? (
          <AdmissionsOverview
            data={data}
            openCycle={openCycle}
            openApplicant={openApplicant}
            openApplication={openApplication}
          />
        ) : activeTab === "eligibility" ? (
          <EligibilityRulesWorkspace
            data={data}
            institutionId={institutionId}
            refresh={load}
            setMessage={setMessage}
            setError={setError}
            busy={busy}
            setBusy={setBusy}
          />
        ) : activeTab === "records" ? (
          <QualificationDocumentWorkspace
            data={processingData}
            selectedApplicationId={selectedApplicationId}
            setSelectedApplicationId={(value) => {
              setSelectedApplicationId(value);
              const application = processingData.applications.find((row) => row.id === value);
              setSelectedApplicantId(application?.applicant_id || "");
            }}
            selectedApplicantId={selectedApplicantId}
            openQualification={openQualification}
            openDocumentUpload={openDocumentUpload}
            handleDownload={handleDownload}
            handleDocumentReview={handleDocumentReview}
            documentNotes={documentNotes}
            setDocumentNotes={setDocumentNotes}
            busy={busy}
          />
        ) : activeTab === "verification" ? (
          <DocumentVerificationQueue
            data={processingData}
            handleDownload={handleDownload}
            handleDocumentReview={handleDocumentReview}
            documentNotes={documentNotes}
            setDocumentNotes={setDocumentNotes}
            setSelectedApplicationId={setSelectedApplicationId}
            setSelectedApplicantId={setSelectedApplicantId}
            setActiveTab={setActiveTab}
            busy={busy}
          />
        ) : activeTab === "waec-verification" ? (
          <WaecVerificationWorkspaceV2
            data={processingData}
            institutionId={institutionId}
            refresh={load}
            setMessage={setMessage}
            setError={setError}
            busy={busy}
            setBusy={setBusy}
          />
        ) : activeTab === "approval" ? (
          <AdmissionsApprovalWorkspace data={processingData} refresh={load} busy={busy} setBusy={setBusy} setMessage={setMessage} setError={setError} confirmAction={confirmAction} />
        ) : activeTab === "eligibility-register" ? (
          <EligibilityRegisterWorkspace
            data={processingData}
            institutionId={institutionId}
            setSelectedApplicationId={setSelectedApplicationId}
            setSelectedApplicantId={setSelectedApplicantId}
            setActiveTab={setActiveTab}
          />
        ) : activeTab === "review" ? (
          <ApplicationReviewWorkspace
            data={processingData}
            selectedApplicationId={selectedApplicationId}
            setSelectedApplicationId={(value) => {
              setSelectedApplicationId(value);
              const application = processingData.applications.find((row) => row.id === value);
              setSelectedApplicantId(application?.applicant_id || "");
            }}
            reviewNotes={reviewNotes}
            setReviewNotes={setReviewNotes}
            handleCompleteReview={handleCompleteReview}
            handleDownload={handleDownload}
            busy={busy}
            setBusy={setBusy}
            setMessage={setMessage}
            setError={setError}
            refresh={load}
            setActiveTab={setActiveTab}
          />
        ) : activeTab === "payment" ? (
          <PaymentSubmissionWorkspace
            data={data}
            selectedApplicationId={selectedApplicationId}
            setSelectedApplicationId={setSelectedApplicationId}
            offlinePayment={offlinePayment}
            setOfflinePayment={setOfflinePayment}
            handleRecordOfflinePayment={handleRecordOfflinePayment}
            handleVerifyOfflinePayment={handleVerifyOfflinePayment}
            handleOnlinePayment={handleOnlinePayment}
            handleSubmitApplication={handleSubmitApplication}
            setActiveTab={setActiveTab}
            busy={busy}
          />
        ) : activeTab === "reports" ? (
          <AdmissionsReportsWorkspace
            data={data}
            handleDownload={handleDownload}
            setSelectedApplicationId={setSelectedApplicationId}
            setSelectedApplicantId={setSelectedApplicantId}
            setActiveTab={setActiveTab}
          />
        ) : (
          <>
            <div className="admissions-toolbar">
              <label className="search-box">
                <Search size={17} />
                <input
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder={`Search ${activeTab}…`}
                />
              </label>

              {activeTab === "cycles" && (
                <button type="button" className="primary-action" onClick={() => openCycle()}>
                  <Plus size={18} /> Add Admission Cycle
                </button>
              )}

              {activeTab === "applicants" && (
                <button type="button" className="primary-action" onClick={() => openApplicant()}>
                  <Plus size={18} /> Add Applicant
                </button>
              )}

              {activeTab === "applications" && (
                <button type="button" className="primary-action" onClick={openApplication}>
                  <Plus size={18} /> Create Application
                </button>
              )}
            </div>

            {loading ? (
              <div className="table-empty">Loading admissions data…</div>
            ) : activeTab === "cycles" ? (
              <CyclesTable rows={filteredCycles} onEdit={openCycle} />
            ) : activeTab === "configuration" ? (
              <AdmissionsConfiguration
                data={data}
                openFeeRule={openFeeRule}
                openRequirement={openRequirement}
              />
            ) : activeTab === "applicants" ? (
              <ApplicantsTable rows={filteredApplicants} onEdit={openApplicant} />
            ) : (
              <ApplicationsTable rows={filteredApplications} />
            )}
          </>
        )}
      </div>

      {modal && (
        <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && setModal(null)}>
          <div className="modal-card admissions-modal">
            <div className="section-title">
              <div>
                <h2>
                  {modal.type === "cycle"
                    ? `${modal.id ? "Edit" : "Add"} Admission Cycle`
                    : modal.type === "feeRule"
                      ? `${modal.id ? "Edit" : "Add"} Application Fee Rule`
                    : modal.type === "requirement"
                      ? `${modal.id ? "Edit" : "Add"} Document Requirement`
                    : modal.type === "applicant"
                      ? `${modal.id ? "Edit" : "Add"} Applicant`
                      : modal.type === "qualification"
                        ? `${modal.id ? "Edit" : "Add"} Qualification`
                        : modal.type === "document"
                          ? "Upload Application Document"
                          : "Create Application"}
                </h2>
                <p>
                  {modal.type === "application"
                    ? "Link an applicant to an admission cycle and programme choice."
                    : modal.type === "document"
                      ? "Upload a scanned/offline or supporting application document."
                      : "Complete the required admissions information."}
                </p>
              </div>

              <button type="button" className="icon-button" onClick={() => setModal(null)}>
                <X size={19} />
              </button>
            </div>

            <form className="user-form" onSubmit={submit}>
              {modal.type === "cycle" ? (
                <CycleForm form={form} setForm={setForm} years={data.years} />
              ) : modal.type === "feeRule" ? (
                <FeeRuleForm form={form} setForm={setForm} data={data} />
              ) : modal.type === "requirement" ? (
                <RequirementForm form={form} setForm={setForm} data={data} />
              ) : modal.type === "applicant" ? (
                <ApplicantForm form={form} setForm={setForm} />
              ) : modal.type === "qualification" ? (
                <QualificationForm form={form} setForm={setForm} />
              ) : modal.type === "document" ? (
                <DocumentUploadForm form={form} setForm={setForm} />
              ) : (
                <ApplicationForm form={form} setForm={setForm} data={data} />
              )}

              <div className="modal-actions">
                <button type="button" className="secondary-button" onClick={() => setModal(null)}>
                  Cancel
                </button>
                <button type="submit" className="primary-action" disabled={busy === "save"}>
                  {busy === "save" ? "Saving…" : "Save"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </section>
  );
}

function AdmissionsOverview({ data, openCycle, openApplicant, openApplication }) {
  const recent = data.applications.slice(0, 5);

  return (
    <div className="admissions-overview">
      <div className="admission-quick-actions">
        <button type="button" onClick={() => openCycle()}><CalendarDays /><strong>New Admission Cycle</strong><span>Configure an intake for an academic year.</span></button>
        <button type="button" onClick={() => openApplicant()}><Users /><strong>Add Applicant</strong><span>Create an applicant master record.</span></button>
        <button type="button" onClick={openApplication}><FileText /><strong>Create Application</strong><span>Attach an applicant to programme choices.</span></button>
      </div>

      <div className="section-title admissions-recent-title">
        <div>
          <h2>Recent Applications</h2>
          <p>Latest applications created in the admissions workspace.</p>
        </div>
      </div>

      <ApplicationsTable rows={recent} />
    </div>
  );
}

function AdmissionsConfiguration({ data, openFeeRule, openRequirement }) {
  const cycleName = (id) => data.cycles.find((x) => x.id === id)?.name || "Unknown cycle";
  return (
    <div className="admissions-overview">
      <div className="section-title">
        <div><h2>Application Fee Rules</h2><p>Configure different fees for Local/International and Undergraduate/Postgraduate applicants.</p></div>
        <button type="button" className="primary-action" onClick={() => openFeeRule()}><Plus size={16}/> Add Fee Rule</button>
      </div>
      <div className="responsive-table"><table className="academic-table admissions-table">
        <thead><tr><th>Cycle</th><th>Category</th><th>Level</th><th>Programme</th><th>Fee</th><th></th></tr></thead>
        <tbody>{data.feeRules.map(r=><tr key={r.id}><td>{cycleName(r.admission_cycle_id)}</td><td>{r.applicant_category}</td><td>{r.admission_level}</td><td>{r.programme ? `${r.programme.code} — ${r.programme.name}` : "All programmes"}</td><td><strong>{r.currency_code} {Number(r.amount).toFixed(2)}</strong></td><td><button className="table-action" type="button" onClick={()=>openFeeRule(r)}><Pencil size={14}/> Edit</button></td></tr>)}
        {!data.feeRules.length && <tr><td colSpan="6" className="table-empty">No Phase 2 fee rules configured yet.</td></tr>}</tbody>
      </table></div>

      <div className="section-title" style={{marginTop:"2rem"}}>
        <div><h2>Document Requirements</h2><p>Define documents required for each admission route.</p></div>
        <button type="button" className="primary-action" onClick={() => openRequirement()}><Plus size={16}/> Add Requirement</button>
      </div>
      <div className="responsive-table"><table className="academic-table admissions-table">
        <thead><tr><th>Cycle</th><th>Document</th><th>Category</th><th>Level</th><th>Programme</th><th></th></tr></thead>
        <tbody>{data.documentRequirements.map(r=><tr key={r.id}><td>{cycleName(r.admission_cycle_id)}</td><td><strong>{r.display_name}</strong><div className="cell-note">{r.document_type}{r.is_required ? " • required" : ""}</div></td><td>{r.applicant_category}</td><td>{r.admission_level}</td><td>{r.programme ? r.programme.code : "All programmes"}</td><td><button className="table-action" type="button" onClick={()=>openRequirement(r)}><Pencil size={14}/> Edit</button></td></tr>)}
        {!data.documentRequirements.length && <tr><td colSpan="6" className="table-empty">No document requirements configured yet.</td></tr>}</tbody>
      </table></div>
    </div>
  );
}

function CyclesTable({ rows, onEdit }) {
  return (
    <div className="responsive-table">
      <table className="academic-table admissions-table">
        <thead><tr><th>Cycle</th><th>Academic Year</th><th>Application Window</th><th>Status</th><th>Actions</th></tr></thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.id}>
              <td><strong>{row.name}</strong><div className="cell-note">Prefix: {row.application_prefix} • {row.admission_level || "undergraduate"} • {row.applicant_scope || "both"}</div></td>
              <td>{row.academic_year?.name || "—"}</td>
              <td>{row.opens_at ? new Date(row.opens_at).toLocaleString() : "Not set"}<div className="cell-note">{row.closes_at ? `Closes ${new Date(row.closes_at).toLocaleString()}` : "No closing date"}</div></td>
              <td><span className={`status-pill ${row.status}`}>{row.status}</span></td>
              <td><button type="button" className="table-action" onClick={() => onEdit(row)}><Pencil size={14} /> Edit</button></td>
            </tr>
          ))}
          {!rows.length && <tr><td colSpan="5" className="table-empty">No admission cycles yet.</td></tr>}
        </tbody>
      </table>
    </div>
  );
}

function ApplicantsTable({ rows, onEdit }) {
  return (
    <div className="responsive-table">
      <table className="academic-table admissions-table">
        <thead><tr><th>Applicant</th><th>Contact</th><th>Location</th><th>Nationality</th><th>Actions</th></tr></thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.id}>
              <td><strong>{applicantName(row)}</strong><div className="cell-note">{row.gender || "—"} {row.date_of_birth ? `• ${row.date_of_birth}` : ""}</div></td>
              <td>{row.email || "—"}<div className="cell-note">{row.phone || "—"}</div></td>
              <td>{[row.city, row.region].filter(Boolean).join(", ") || "—"}</td>
              <td>{row.nationality || "—"}</td>
              <td><button type="button" className="table-action" onClick={() => onEdit(row)}><Pencil size={14} /> Edit</button></td>
            </tr>
          ))}
          {!rows.length && <tr><td colSpan="5" className="table-empty">No applicants yet.</td></tr>}
        </tbody>
      </table>
    </div>
  );
}

function ApplicationsTable({ rows }) {
  return (
    <div className="responsive-table">
      <table className="academic-table admissions-table">
        <thead><tr><th>Application</th><th>Applicant</th><th>Cycle</th><th>First Choice</th><th>Status</th></tr></thead>
        <tbody>
          {rows.map((row) => {
            const first = choiceProgramme(row, 1);
            return (
              <tr key={row.id}>
                <td><strong>{row.application_number}</strong><div className="cell-note">{row.entry_type}</div></td>
                <td>{applicantName(row.applicant)}<div className="cell-note">{row.applicant?.email || "—"}</div></td>
                <td>{row.admission_cycle?.name || "—"}</td>
                <td>{first ? `${first.code} — ${first.name}` : "—"}</td>
                <td><span className={`status-pill ${row.status}`}>{row.status}</span></td>
              </tr>
            );
          })}
          {!rows.length && <tr><td colSpan="5" className="table-empty">No applications yet.</td></tr>}
        </tbody>
      </table>
    </div>
  );
}


function QualificationDocumentWorkspace({
  data,
  selectedApplicationId,
  setSelectedApplicationId,
  selectedApplicantId,
  openQualification,
  openDocumentUpload,
  handleDownload,
  handleDocumentReview,
  documentNotes,
  setDocumentNotes,
  busy,
}) {
  const application = data.applications.find(
    (row) => row.id === selectedApplicationId
  );

  const qualifications = data.qualifications.filter(
    (row) => row.applicant_id === selectedApplicantId
  );

  const documents = data.documents.filter(
    (row) => row.application_id === selectedApplicationId
  );

  return (
    <div className="admission-records-workspace">
      <div className="admission-record-selector">
        <label>
          Application
          <select
            value={selectedApplicationId}
            onChange={(e) => setSelectedApplicationId(e.target.value)}
          >
            <option value="">Select application…</option>
            {data.applications.map((row) => (
              <option key={row.id} value={row.id}>
                {row.application_number} — {applicantName(row.applicant)}
              </option>
            ))}
          </select>
        </label>
      </div>

      {!application ? (
        <div className="table-empty">
          Select an application to manage qualifications and documents.
        </div>
      ) : (
        <div className="admission-record-columns">
          <section className="admission-subcard">
            <div className="section-title">
              <div>
                <h2>Qualifications</h2>
                <p>{applicantName(application.applicant)}</p>
              </div>
              <button type="button" className="primary-action" onClick={() => openQualification()}>
                <Plus size={17} /> Add Qualification
              </button>
            </div>

            <div className="responsive-table">
              <table className="academic-table admissions-detail-table">
                <thead>
                  <tr>
                    <th>Qualification</th>
                    <th>Institution / Body</th>
                    <th>Year</th>
                    <th>Result</th>
                    <th>Action</th>
                  </tr>
                </thead>
                <tbody>
                  {qualifications.map((row) => (
                    <tr key={row.id}>
                      <td>
                        <strong>{row.qualification_type}</strong>
                        <div className="cell-note">{row.index_number || "—"}</div>
                      </td>
                      <td>
                        {row.institution_name || "—"}
                        <div className="cell-note">{row.examining_body || ""}</div>
                      </td>
                      <td>{row.completion_year || "—"}</td>
                      <td>{row.overall_result || "—"}</td>
                      <td>
                        <button type="button" className="table-action" onClick={() => openQualification(row)}>
                          <Pencil size={14} /> Edit
                        </button>
                      </td>
                    </tr>
                  ))}
                  {!qualifications.length && (
                    <tr>
                      <td colSpan="5" className="table-empty">
                        No qualifications recorded.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </section>

          <section className="admission-subcard">
            <div className="section-title">
              <div>
                <h2>Application Documents</h2>
                <p>Scans, certificates, results, ID and other supporting files.</p>
              </div>
              <button type="button" className="primary-action" onClick={openDocumentUpload}>
                <Upload size={17} /> Upload Document
              </button>
            </div>

            <div className="admission-document-list">
              {documents.map((document) => (
                <article key={document.id} className="admission-document-card">
                  <div className="admission-document-main">
                    <div>
                      <strong>{document.document_type}</strong>
                      <span>{document.file_name}</span>
                    </div>
                    <span className={`status-pill ${document.verification_status}`}>
                      {document.verification_status}
                    </span>
                  </div>

                  <div className="admission-document-actions">
                    <button
                      type="button"
                      className="table-action"
                      disabled={!!busy}
                      onClick={() => handleDownload(document)}
                    >
                      <Download size={14} /> Download
                    </button>

                    <input
                      value={documentNotes[document.id] || ""}
                      onChange={(e) =>
                        setDocumentNotes((current) => ({
                          ...current,
                          [document.id]: e.target.value,
                        }))
                      }
                      placeholder="Verification note (optional)"
                    />

                    <button
                      type="button"
                      className="table-action"
                      disabled={!!busy}
                      onClick={() => handleDocumentReview(document.id, "verified")}
                    >
                      <BadgeCheck size={14} /> Verify
                    </button>

                    <button
                      type="button"
                      className="table-action danger"
                      disabled={!!busy}
                      onClick={() => handleDocumentReview(document.id, "rejected")}
                    >
                      <BadgeX size={14} /> Reject
                    </button>
                  </div>
                </article>
              ))}

              {!documents.length && (
                <div className="table-empty">No application documents uploaded.</div>
              )}
            </div>
          </section>
        </div>
      )}
    </div>
  );
}


function normalizeReportText(value = "") {
  return String(value ?? "").replace(/\s+/g, " ").trim();
}

function csvCell(value) {
  const text = normalizeReportText(value).replaceAll('"', '""');
  return `"${text}"`;
}

function downloadCsvFile(filename, headers, rows) {
  const csv = [headers, ...rows]
    .map((row) => row.map(csvCell).join(","))
    .join("\n");
  const blob = new Blob(["\ufeff" + csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}

function printHtmlReport(title, subtitle, headers, rows, summaryHtml = "") {

  const bodyRows = rows.map((row) => `<tr>${row.map((cell) => `<td>${escapeHtml(normalizeReportText(cell))}</td>`).join("")}</tr>`).join("");
  printLegacyDocument122("UniMIS Admissions Report",`<!doctype html><html><head><title>${escapeHtml(title)}</title><style>
    body{font-family:Arial,sans-serif;padding:30px;color:#17233b}h1{color:#123b72;margin-bottom:5px}.subtitle{color:#667085;margin-bottom:18px}.summary{display:flex;gap:10px;flex-wrap:wrap;margin:14px 0 20px}.summary>div{border:1px solid #dfe4ec;border-radius:8px;padding:10px 13px;background:#f8fafc}table{width:100%;border-collapse:collapse;font-size:11px}th,td{border:1px solid #dfe4ec;padding:7px;text-align:left;vertical-align:top}th{background:#eef3f8;color:#123b72}@media print{body{padding:10px}}
  </style></head><body><h1>${escapeHtml(title)}</h1><div class="subtitle">${escapeHtml(subtitle)} • Generated ${escapeHtml(new Date().toLocaleString())}</div>${summaryHtml}<table><thead><tr>${headers.map((h)=>`<th>${escapeHtml(h)}</th>`).join("")}</tr></thead><tbody>${bodyRows || `<tr><td colspan="${headers.length}">No records</td></tr>`}</tbody></table></body></html>`);

}


function WaecVerificationWorkspace({ data, refresh, setMessage, setError, busy, setBusy }) {
  const [status, setStatus] = useState("unverified");
  const [search, setSearch] = useState(() => {
    const focus = sessionStorage.getItem("unimis_waec_focus_application") || "";
    sessionStorage.removeItem("unimis_waec_focus_application");
    return focus;
  });
  const [cycleId, setCycleId] = useState("all");

  const applicationByApplicant = useMemo(() => {
    const map = new Map();
    data.applications.forEach((application) => {
      const current = map.get(application.applicant_id);
      if (!current || new Date(application.created_at) > new Date(current.created_at)) {
        map.set(application.applicant_id, application);
      }
    });
    return map;
  }, [data.applications]);

  const rows = useMemo(() => data.qualifications
    .filter((q) => (q.qualification_type || "").toUpperCase() === "WASSCE")
    .map((q) => {
      const application = applicationByApplicant.get(q.applicant_id);
      const applicant = data.applicants.find((x) => x.id === q.applicant_id);
      const results = data.subjectResults.filter((x) => x.qualification_id === q.id);
      return { q, application, applicant, results };
    })
    .filter(({ q, application, applicant }) => {
      if (status !== "all" && (q.verification_status || "unverified") !== status) return false;
      if (cycleId !== "all" && application?.admission_cycle_id !== cycleId) return false;
      const hay = `${application?.application_number || ""} ${applicantName(applicant)} ${q.index_number || ""}`.toLowerCase();
      return hay.includes(search.toLowerCase());
    }), [data.qualifications, data.subjectResults, data.applicants, applicationByApplicant, status, cycleId, search]);

  function exportBatch() {
    downloadCsvFile(
      `unimis-waec-verification-batch-${new Date().toISOString().slice(0,10)}.csv`,
      ["Application","Applicant","Index Number","Exam Type","Exam Year","Sitting","Entered Subjects / Grades"],
      rows.map(({q,application,applicant,results}) => [
        application?.application_number || "",
        applicantName(applicant),
        q.index_number || "",
        q.qualification_type || "WASSCE",
        q.completion_year || "",
        q.exam_sitting || "",
        results.map((r)=>`${r.subject_name}:${r.grade}`).join("; "),
      ])
    );
  }

  async function record(row, nextStatus) {
    const reference = window.prompt(
      nextStatus === "verified"
        ? "Enter the WAEC verification/reference number (recommended):"
        : "Enter a WAEC reference or short reason for the mismatch:",
      row.q.verification_reference || ""
    );
    if (reference === null) return;
    const notes = window.prompt("Verification notes (optional):", "") ?? "";
    setBusy(`waec-${row.q.id}`);
    setError("");
    const result = await recordWaecVerification({
      qualificationId: row.q.id,
      status: nextStatus,
      method: "waec_portal",
      reference,
      notes,
    });
    if (result.error) setError(result.error.message);
    else {
      setMessage(nextStatus === "verified" ? "Official WAEC verification recorded." : "WAEC result mismatch recorded.");
      await refresh();
    }
    setBusy("");
  }

  const verified = data.qualifications.filter((q)=>(q.qualification_type||"").toUpperCase()==="WASSCE" && q.verification_status==="verified").length;
  const mismatched = data.qualifications.filter((q)=>(q.qualification_type||"").toUpperCase()==="WASSCE" && q.verification_status==="mismatch").length;
  const total = data.qualifications.filter((q)=>(q.qualification_type||"").toUpperCase()==="WASSCE").length;

  return <div className="waec-workspace">
    <div className="section-title">
      <div>
        <h2>WAEC Result Verification</h2>
        <p>Institutional verification queue for WASSCE results. Academic eligibility may be provisional before this step; admission approval should rely on verified results.</p>
      </div>
      <div className="report-actions">
        <a className="secondary-button" href="https://rvs.waecdirect.org/home/index" target="_blank" rel="noreferrer"><ExternalLink size={16}/> Open WAEC RVS</a>
        <button type="button" className="secondary-button" onClick={exportBatch}><FileSpreadsheet size={16}/> Prepare Batch CSV</button>
      </div>
    </div>

    <div className="report-summary-grid">
      <div><span>WASSCE records</span><strong>{total}</strong></div>
      <div><span>Awaiting verification</span><strong>{total-verified-mismatched}</strong></div>
      <div><span>WAEC verified</span><strong>{verified}</strong></div>
      <div><span>Mismatch</span><strong>{mismatched}</strong></div>
    </div>

    <div className="waec-guidance-card">
      <ShieldCheck size={22}/>
      <div><strong>Current institutional workflow</strong><p>Use WAEC Ghana's authorised Result Verification System for the official check, then record the reference and outcome here. The same queue is API-ready: when the university receives WAEC REST API credentials, verification can be performed server-side without changing applicant records.</p></div>
    </div>

    <div className="report-filter-row">
      <input value={search} onChange={(e)=>setSearch(e.target.value)} placeholder="Search applicant, application or index number..." />
      <select value={cycleId} onChange={(e)=>setCycleId(e.target.value)}><option value="all">All cycles</option>{data.cycles.map((c)=><option key={c.id} value={c.id}>{c.name}</option>)}</select>
      <select value={status} onChange={(e)=>setStatus(e.target.value)}><option value="all">All statuses</option><option value="unverified">Awaiting verification</option><option value="verified">Verified</option><option value="mismatch">Mismatch</option></select>
    </div>

    <div className="responsive-table"><table className="academic-table admissions-detail-table">
      <thead><tr><th>Applicant</th><th>WAEC identity</th><th>Entered result</th><th>Status</th><th>Action</th></tr></thead>
      <tbody>{rows.map((row)=><tr key={row.q.id}>
        <td><strong>{row.application?.application_number || "—"}</strong><span className="table-subtext">{applicantName(row.applicant)}</span></td>
        <td><strong>{row.q.index_number || "No index number"}</strong><span className="table-subtext">{row.q.completion_year || "—"} • {row.q.exam_sitting || "WASSCE"}</span></td>
        <td><strong>{row.results.length} subject(s)</strong><span className="table-subtext">{row.results.map((r)=>`${r.subject_name} ${r.grade}`).join(" • ") || "No structured grades"}</span></td>
        <td><span className={`status-pill ${row.q.verification_status || "unverified"}`}>{row.q.verification_status || "unverified"}</span>{row.q.verification_reference && <span className="table-subtext">Ref: {row.q.verification_reference}</span>}</td>
        <td><div className="queue-actions">
          <button type="button" className="table-action success" disabled={!!busy || row.q.verification_status==="verified"} onClick={()=>record(row,"verified")}><BadgeCheck size={14}/> Record WAEC Verified</button>
          <button type="button" className="table-action danger" disabled={!!busy} onClick={()=>record(row,"mismatch")}><BadgeX size={14}/> Mismatch</button>
        </div></td>
      </tr>)}{!rows.length&&<tr><td colSpan="5" className="table-empty">No WASSCE records match these filters.</td></tr>}</tbody>
    </table></div>
  </div>;
}


function DocumentVerificationQueue({
  data,
  handleDownload,
  handleDocumentReview,
  documentNotes,
  setDocumentNotes,
  setSelectedApplicationId,
  setSelectedApplicantId,
  setActiveTab,
  busy,
}) {
  const [statusFilter, setStatusFilter] = useState("pending");
  const [typeFilter, setTypeFilter] = useState("all");
  const [cycleFilter, setCycleFilter] = useState("all");
  const [queueQuery, setQueueQuery] = useState("");

  const applicationMap = useMemo(() => new Map(data.applications.map((row) => [row.id, row])), [data.applications]);
  const documentTypes = useMemo(() => [...new Set(data.documents.map((row) => row.document_type).filter(Boolean))].sort(), [data.documents]);

  const rows = useMemo(() => data.documents.map((document) => {
    const application = applicationMap.get(document.application_id);
    return { document, application, applicant: application?.applicant };
  }).filter(({ document, application, applicant }) => {
    if (!application) return false;
    if (statusFilter !== "all" && document.verification_status !== statusFilter) return false;
    if (typeFilter !== "all" && document.document_type !== typeFilter) return false;
    if (cycleFilter !== "all" && application.admission_cycle_id !== cycleFilter) return false;
    const haystack = `${application.application_number || ""} ${applicantName(applicant)} ${document.document_type || ""} ${document.file_name || ""}`.toLowerCase();
    return haystack.includes(queueQuery.trim().toLowerCase());
  }), [data.documents, applicationMap, statusFilter, typeFilter, cycleFilter, queueQuery]);

  const pending = data.documents.filter((d) => d.verification_status === "pending").length;
  const verified = data.documents.filter((d) => d.verification_status === "verified").length;
  const rejected = data.documents.filter((d) => d.verification_status === "rejected").length;

  function exportQueueCsv() {
    downloadCsvFile(
      `unimis-document-verification-${new Date().toISOString().slice(0,10)}.csv`,
      ["Application", "Applicant", "Cycle", "Document Type", "File Name", "Status", "Uploaded"],
      rows.map(({ document, application, applicant }) => [
        application.application_number,
        applicantName(applicant),
        application.admission_cycle?.name,
        document.document_type,
        document.file_name,
        document.verification_status,
        document.created_at ? new Date(document.created_at).toLocaleString() : "",
      ])
    );
  }

  function printQueue() {
    printHtmlReport(
      "UniMIS Document Verification Queue",
      `${rows.length} document(s) in the current filtered queue`,
      ["Application", "Applicant", "Cycle", "Document", "File", "Status", "Uploaded"],
      rows.map(({ document, application, applicant }) => [
        application.application_number,
        applicantName(applicant),
        application.admission_cycle?.name,
        document.document_type,
        document.file_name,
        document.verification_status,
        document.created_at ? new Date(document.created_at).toLocaleString() : "",
      ]),
      `<div class="summary"><div><strong>Pending</strong><br>${pending}</div><div><strong>Verified</strong><br>${verified}</div><div><strong>Rejected</strong><br>${rejected}</div></div>`
    );
  }

  function openApplication(application) {
    setSelectedApplicationId(application.id);
    setSelectedApplicantId(application.applicant_id || "");
    setActiveTab("records");
  }

  return (
    <div className="verification-queue-workspace">
      <section className="admission-subcard verification-queue-header">
        <div className="section-title">
          <div>
            <h2>Document Verification Queue</h2>
            <p>Work from one institution-wide queue instead of opening applicants one by one.</p>
          </div>
          <div className="report-actions">
            <button type="button" className="secondary-button" onClick={exportQueueCsv}><FileSpreadsheet size={16}/> Export CSV</button>
            <button type="button" className="secondary-button" onClick={printQueue}><Printer size={16}/> Print / Save PDF</button>
          </div>
        </div>

        <div className="verification-summary-grid">
          <div><span>Pending</span><strong>{pending}</strong></div>
          <div><span>Verified</span><strong>{verified}</strong></div>
          <div><span>Rejected</span><strong>{rejected}</strong></div>
          <div><span>Current queue</span><strong>{rows.length}</strong></div>
        </div>

        <div className="verification-filters">
          <label>Status<select value={statusFilter} onChange={(e)=>setStatusFilter(e.target.value)}><option value="pending">Pending verification</option><option value="verified">Verified</option><option value="rejected">Rejected</option><option value="all">All statuses</option></select></label>
          <label>Document<select value={typeFilter} onChange={(e)=>setTypeFilter(e.target.value)}><option value="all">All document types</option>{documentTypes.map((type)=><option key={type} value={type}>{type}</option>)}</select></label>
          <label>Cycle<select value={cycleFilter} onChange={(e)=>setCycleFilter(e.target.value)}><option value="all">All cycles</option>{data.cycles.map((cycle)=><option key={cycle.id} value={cycle.id}>{cycle.name}</option>)}</select></label>
          <label>Search<input value={queueQuery} onChange={(e)=>setQueueQuery(e.target.value)} placeholder="Applicant, application, file..." /></label>
        </div>
      </section>

      <div className="responsive-table">
        <table className="academic-table admissions-detail-table verification-queue-table">
          <thead><tr><th>Application / Applicant</th><th>Document</th><th>Status</th><th>Verification note</th><th>Actions</th></tr></thead>
          <tbody>
            {rows.map(({ document, application, applicant }) => (
              <tr key={document.id}>
                <td><strong>{application.application_number || "—"}</strong><span className="table-subtext">{applicantName(applicant)} • {application.admission_cycle?.name || ""}</span></td>
                <td><strong>{document.document_type}</strong><span className="table-subtext">{document.file_name}</span></td>
                <td><span className={`status-pill ${document.verification_status}`}>{document.verification_status}</span></td>
                <td><input className="queue-note-input" value={documentNotes[document.id] || ""} onChange={(e)=>setDocumentNotes((current)=>({...current,[document.id]:e.target.value}))} placeholder="Optional note" /></td>
                <td><div className="queue-actions">
                  <button type="button" className="table-action" disabled={!!busy} onClick={()=>handleDownload(document)}><Download size={14}/> View</button>
                  {document.verification_status !== "verified" && <button type="button" className="table-action" disabled={!!busy} onClick={()=>handleDocumentReview(document.id,"verified")}><BadgeCheck size={14}/> Verify</button>}
                  {document.verification_status !== "rejected" && <button type="button" className="table-action danger" disabled={!!busy} onClick={()=>handleDocumentReview(document.id,"rejected")}><BadgeX size={14}/> Reject</button>}
                  <button type="button" className="table-action" onClick={()=>openApplication(application)}><ExternalLink size={14}/> Application</button>
                </div></td>
              </tr>
            ))}
            {!rows.length && <tr><td colSpan="5" className="table-empty">No documents match the current verification filters.</td></tr>}
          </tbody>
        </table>
      </div>
      <div className="form-note verification-note">WAEC result verification is deliberately not simulated here. UniMIS will later connect this queue to an authorised WAEC verification provider/API or bulk verification workflow.</div>
    </div>
  );
}

function AdmissionsReportsWorkspace({ data, handleDownload, setSelectedApplicationId, setSelectedApplicantId, setActiveTab }) {
  const [reportType, setReportType] = useState("documents");
  const [cycleFilter, setCycleFilter] = useState("all");
  const [statusFilter, setStatusFilter] = useState("all");

  const applicationMap = useMemo(() => new Map(data.applications.map((row) => [row.id, row])), [data.applications]);

  const documentRows = useMemo(() => data.documents.map((document) => {
    const application = applicationMap.get(document.application_id);
    return { document, application, applicant: application?.applicant };
  }).filter(({ document, application }) => application && (cycleFilter === "all" || application.admission_cycle_id === cycleFilter) && (statusFilter === "all" || document.verification_status === statusFilter)), [data.documents, applicationMap, cycleFilter, statusFilter]);

  const applicationRows = useMemo(() => data.applications.filter((application) => (cycleFilter === "all" || application.admission_cycle_id === cycleFilter) && (statusFilter === "all" || application.status === statusFilter)), [data.applications, cycleFilter, statusFilter]);

  const reportRows = reportType === "documents" ? documentRows : applicationRows;

  function exportCurrent() {
    if (reportType === "documents") {
      downloadCsvFile(`unimis-admissions-documents-${new Date().toISOString().slice(0,10)}.csv`, ["Application","Applicant","Cycle","Document Type","File","Verification Status","Uploaded"], documentRows.map(({document,application,applicant})=>[application.application_number,applicantName(applicant),application.admission_cycle?.name,document.document_type,document.file_name,document.verification_status,document.created_at ? new Date(document.created_at).toLocaleString() : ""]));
    } else {
      downloadCsvFile(`unimis-admissions-applications-${new Date().toISOString().slice(0,10)}.csv`, ["Application","Applicant","Cycle","Programme","Status","Payment","Submitted","Reviewed"], applicationRows.map((application)=>[application.application_number,applicantName(application.applicant),application.admission_cycle?.name,choiceProgramme(application,1)?.name,application.status,application.payment_status,application.submitted_at ? new Date(application.submitted_at).toLocaleString() : "",application.reviewed_at ? new Date(application.reviewed_at).toLocaleString() : ""]));
    }
  }

  function printCurrent() {
    if (reportType === "documents") {
      printHtmlReport("UniMIS Admissions Document Report", `${documentRows.length} document record(s)`, ["Application","Applicant","Cycle","Document","File","Status"], documentRows.map(({document,application,applicant})=>[application.application_number,applicantName(applicant),application.admission_cycle?.name,document.document_type,document.file_name,document.verification_status]));
    } else {
      printHtmlReport("UniMIS Admissions Application Report", `${applicationRows.length} application record(s)`, ["Application","Applicant","Cycle","Programme","Status","Payment","Submitted","Reviewed"], applicationRows.map((application)=>[application.application_number,applicantName(application.applicant),application.admission_cycle?.name,choiceProgramme(application,1)?.name,application.status,application.payment_status,application.submitted_at ? new Date(application.submitted_at).toLocaleDateString() : "—",application.reviewed_at ? new Date(application.reviewed_at).toLocaleDateString() : "—"]));
    }
  }

  const documentPending = documentRows.filter((r)=>r.document.verification_status === "pending").length;
  const submitted = applicationRows.filter((r)=>Boolean(r.submitted_at)).length;
  const reviewed = applicationRows.filter((r)=>Boolean(r.reviewed_at)).length;

  return (
    <div className="admissions-reports-workspace">
      <section className="admission-subcard reports-hero-card">
        <div className="section-title">
          <div><h2>Admissions Reports Centre</h2><p>Operational reports for applications, documents and verification. Reports follow the current filters and can be exported.</p></div>
          <div className="report-actions"><button type="button" className="secondary-button" onClick={exportCurrent}><FileSpreadsheet size={16}/> Export CSV</button><button type="button" className="secondary-button" onClick={printCurrent}><Printer size={16}/> Print / Save PDF</button></div>
        </div>
        <div className="reports-filter-grid">
          <label>Report<select value={reportType} onChange={(e)=>{setReportType(e.target.value);setStatusFilter("all")}}><option value="documents">Documents & Verification</option><option value="applications">Applications</option></select></label>
          <label>Admission cycle<select value={cycleFilter} onChange={(e)=>setCycleFilter(e.target.value)}><option value="all">All cycles</option>{data.cycles.map((cycle)=><option key={cycle.id} value={cycle.id}>{cycle.name}</option>)}</select></label>
          <label>Status<select value={statusFilter} onChange={(e)=>setStatusFilter(e.target.value)}><option value="all">All statuses</option>{reportType === "documents" ? <><option value="pending">Pending verification</option><option value="verified">Verified</option><option value="rejected">Rejected</option></> : <><option value="draft">Draft</option><option value="submitted">Submitted</option><option value="under_review">Under review</option><option value="reviewed">Reviewed</option><option value="offered">Offered</option><option value="rejected">Rejected</option></>}</select></label>
        </div>
        <div className="reports-summary-grid">
          {reportType === "documents" ? <><div><span>Documents</span><strong>{documentRows.length}</strong></div><div><span>Pending verification</span><strong>{documentPending}</strong></div><div><span>Verified</span><strong>{documentRows.filter((r)=>r.document.verification_status === "verified").length}</strong></div><div><span>Rejected</span><strong>{documentRows.filter((r)=>r.document.verification_status === "rejected").length}</strong></div></> : <><div><span>Applications</span><strong>{applicationRows.length}</strong></div><div><span>Submitted</span><strong>{submitted}</strong></div><div><span>Reviewed</span><strong>{reviewed}</strong></div><div><span>Pending review</span><strong>{applicationRows.filter((r)=>r.submitted_at && !r.reviewed_at).length}</strong></div></>}
        </div>
      </section>

      {reportType === "documents" ? (
        <div className="responsive-table"><table className="academic-table admissions-detail-table"><thead><tr><th>Application / Applicant</th><th>Document</th><th>Status</th><th>Uploaded</th><th>Action</th></tr></thead><tbody>{documentRows.map(({document,application,applicant})=><tr key={document.id}><td><strong>{application.application_number}</strong><span className="table-subtext">{applicantName(applicant)} • {application.admission_cycle?.name}</span></td><td><strong>{document.document_type}</strong><span className="table-subtext">{document.file_name}</span></td><td><span className={`status-pill ${document.verification_status}`}>{document.verification_status}</span></td><td>{document.created_at ? new Date(document.created_at).toLocaleString() : "—"}</td><td><div className="queue-actions"><button className="table-action" type="button" onClick={()=>handleDownload(document)}><Download size={14}/> View</button><button className="table-action" type="button" onClick={()=>{setSelectedApplicationId(application.id);setSelectedApplicantId(application.applicant_id || "");setActiveTab("verification")}}><ListChecks size={14}/> Verify</button></div></td></tr>)}{!documentRows.length&&<tr><td colSpan="5" className="table-empty">No document records match these filters.</td></tr>}</tbody></table></div>
      ) : (
        <div className="responsive-table"><table className="academic-table admissions-detail-table"><thead><tr><th>Application / Applicant</th><th>Programme</th><th>Status</th><th>Payment</th><th>Submitted</th><th>Reviewed</th></tr></thead><tbody>{applicationRows.map((application)=><tr key={application.id}><td><strong>{application.application_number}</strong><span className="table-subtext">{applicantName(application.applicant)} • {application.admission_cycle?.name}</span></td><td>{choiceProgramme(application,1)?.name || "—"}</td><td><span className={`status-pill ${application.status || "draft"}`}>{application.status || "draft"}</span></td><td>{application.payment_status || "—"}</td><td>{application.submitted_at ? new Date(application.submitted_at).toLocaleString() : "—"}</td><td>{application.reviewed_at ? new Date(application.reviewed_at).toLocaleString() : "—"}</td></tr>)}{!applicationRows.length&&<tr><td colSpan="6" className="table-empty">No applications match these filters.</td></tr>}</tbody></table></div>
      )}
    </div>
  );
}

function EligibilityRulesWorkspace({
  data,
  institutionId,
  refresh,
  setMessage,
  setError,
  busy,
  setBusy,
}) {
  const STANDARD_ELECTIVES = [
    "Elective Mathematics",
    "Physics",
    "Chemistry",
    "Biology",
    "General Agriculture",
    "Economics",
    "Geography",
    "Government",
    "History",
    "Literature in English",
    "Accounting",
    "Business Management",
    "ICT",
    "Technical Drawing",
    "Applied Electricity",
    "Electronics",
  ];

  const emptyRule = () => ({
    id: null,
    programme_id: "",
    admission_cycle_id: "",
    qualification_type: "WASSCE",
    max_aggregate: "24",
    minimum_elective_passes: "3",
    default_max_grade_rank: "6",
    notes: "",
    subject_rules: [
      { subject_name: "English Language", subject_group: "required", max_grade_rank: "6" },
      { subject_name: "Core Mathematics", subject_group: "required", max_grade_rank: "6" },
      { subject_name: "Integrated Science", subject_group: "required", max_grade_rank: "6" },
    ],
  });

  const [form, setForm] = useState(emptyRule);

  function resetForm() {
    setForm(emptyRule());
  }

  function editRule(rule) {
    setForm({
      id: rule.id,
      programme_id: rule.programme_id,
      admission_cycle_id: rule.admission_cycle_id || "",
      qualification_type: rule.qualification_type || "WASSCE",
      max_aggregate: rule.max_aggregate ?? "",
      minimum_elective_passes: rule.minimum_elective_passes ?? 3,
      default_max_grade_rank: rule.default_max_grade_rank ?? 6,
      notes: rule.notes || "",
      subject_rules: (rule.subjects || [])
        .slice()
        .sort((a, b) => (a.sequence_no || 0) - (b.sequence_no || 0))
        .map((row) => ({
          subject_name: row.subject_name || "",
          subject_group: row.subject_group || "required",
          max_grade_rank: row.max_grade_rank ?? rule.default_max_grade_rank ?? 6,
        })),
    });
  }

  function setSubject(index, key, value) {
    const next = [...form.subject_rules];
    next[index] = { ...next[index], [key]: value };
    setForm({ ...form, subject_rules: next });
  }

  function addSubject(group = "required") {
    setForm({
      ...form,
      subject_rules: [
        ...form.subject_rules,
        { subject_name: "", subject_group: group, max_grade_rank: form.default_max_grade_rank || "6" },
      ],
    });
  }

  function removeSubject(index) {
    setForm({
      ...form,
      subject_rules: form.subject_rules.filter((_, i) => i !== index),
    });
  }

  function applyGeneralWassceTemplate() {
    setForm({
      ...form,
      qualification_type: "WASSCE",
      max_aggregate: "24",
      minimum_elective_passes: "3",
      default_max_grade_rank: "6",
      subject_rules: [
        { subject_name: "English Language", subject_group: "required", max_grade_rank: "6" },
        { subject_name: "Core Mathematics", subject_group: "required", max_grade_rank: "6" },
        { subject_name: "Integrated Science", subject_group: "required", max_grade_rank: "6" },
        ...STANDARD_ELECTIVES.map((subject_name) => ({
          subject_name,
          subject_group: "elective_pool",
          max_grade_rank: "6",
        })),
      ],
    });
  }

  async function saveRule(e) {
    e.preventDefault();
    setError("");
    setMessage("");

    if (!form.programme_id) {
      setError("Select a programme for the admission rule.");
      return;
    }

    const subjects = form.subject_rules.filter((row) => row.subject_name.trim());
    if (!subjects.length) {
      setError("Add at least one subject requirement.");
      return;
    }

    setBusy("eligibility-rule");
    const result = await saveProgrammeAdmissionRule(institutionId, {
      ...form,
      subject_rules: subjects,
    });

    if (result.error) setError(result.error.message);
    else {
      setMessage(form.id ? "Programme admission rule updated." : "Programme admission rule created.");
      resetForm();
      await refresh();
    }
    setBusy("");
  }

  const configuredProgrammeIds = new Set((data.eligibilityRules || []).map((r) => r.programme_id));

  return (
    <div className="eligibility-rules-workspace">
      <div className="review-summary-grid eligibility-rule-stats">
        <div><span>Active rules</span><strong>{data.eligibilityRules?.length || 0}</strong></div>
        <div><span>Programmes configured</span><strong>{configuredProgrammeIds.size}</strong></div>
        <div><span>Active programmes</span><strong>{data.programmes.length}</strong></div>
        <div><span>Default WAEC pass</span><strong>A1–C6</strong></div>
      </div>

      <section className="admission-subcard eligibility-explainer">
        <div className="section-title">
          <div>
            <h2>Programme Academic Eligibility Rules</h2>
            <p>
              Configure the subjects and aggregate required by each programme. UniMIS compares an applicant's
              structured WASSCE/SSSCE grades with these rules automatically. These rules are institutional rules —
              they are not hard-coded KNUST rules.
            </p>
          </div>
          <button type="button" className="secondary-button" onClick={applyGeneralWassceTemplate}>
            <GraduationCap size={16}/> Load general WASSCE template
          </button>
        </div>
      </section>

      <div className="eligibility-rules-grid">
        <form className="admission-subcard eligibility-rule-form" onSubmit={saveRule}>
          <div className="section-title">
            <div>
              <h3>{form.id ? "Edit admission rule" : "New admission rule"}</h3>
              <p>Use required subjects for compulsory subjects and Elective Pool for subjects from which a minimum number must pass.</p>
            </div>
            {form.id && <button type="button" className="table-action" onClick={resetForm}>New rule</button>}
          </div>

          <div className="form-grid two-column-grid">
            <label>
              Programme
              <select required value={form.programme_id} onChange={(e) => setForm({ ...form, programme_id: e.target.value })}>
                <option value="">Select programme…</option>
                {data.programmes.map((programme) => (
                  <option key={programme.id} value={programme.id}>{programme.code} — {programme.name}</option>
                ))}
              </select>
            </label>
            <label>
              Admission cycle
              <select value={form.admission_cycle_id} onChange={(e) => setForm({ ...form, admission_cycle_id: e.target.value })}>
                <option value="">All cycles / default rule</option>
                {data.cycles.map((cycle) => <option key={cycle.id} value={cycle.id}>{cycle.name}</option>)}
              </select>
            </label>
            <label>
              Qualification
              <select value={form.qualification_type} onChange={(e) => setForm({ ...form, qualification_type: e.target.value })}>
                <option value="WASSCE">WASSCE</option>
              </select>
            </label>
            <label>
              Maximum aggregate
              <input type="number" min="1" max="54" value={form.max_aggregate} onChange={(e) => setForm({ ...form, max_aggregate: e.target.value })}/>
            </label>
            <label>
              Elective passes required
              <input type="number" min="0" max="9" value={form.minimum_elective_passes} onChange={(e) => setForm({ ...form, minimum_elective_passes: e.target.value })}/>
            </label>
            <label>
              Default worst accepted grade
              <select value={form.default_max_grade_rank} onChange={(e) => setForm({ ...form, default_max_grade_rank: e.target.value })}>
                <option value="1">A1</option><option value="2">B2</option><option value="3">B3</option>
                <option value="4">C4</option><option value="5">C5</option><option value="6">C6</option>
                <option value="7">D7</option><option value="8">E8</option><option value="9">F9</option>
              </select>
            </label>
          </div>

          <div className="eligibility-subject-header">
            <div><strong>Subject requirements</strong><span>Required = must pass. Elective Pool = choose the configured minimum.</span></div>
            <div>
              <button type="button" className="table-action" onClick={() => addSubject("required")}><Plus size={14}/> Required</button>
              <button type="button" className="table-action" onClick={() => addSubject("elective_pool")}><Plus size={14}/> Elective</button>
            </div>
          </div>

          <div className="eligibility-subject-editor">
            {form.subject_rules.map((row, index) => (
              <div className="eligibility-subject-row" key={`${index}-${row.subject_name}`}>
                <input value={row.subject_name} onChange={(e) => setSubject(index, "subject_name", e.target.value)} placeholder="Subject name"/>
                <select value={row.subject_group} onChange={(e) => setSubject(index, "subject_group", e.target.value)}>
                  <option value="required">Required</option>
                  <option value="elective_pool">Elective Pool</option>
                </select>
                <select value={row.max_grade_rank} onChange={(e) => setSubject(index, "max_grade_rank", e.target.value)}>
                  <option value="1">A1</option><option value="2">B2</option><option value="3">B3</option>
                  <option value="4">C4</option><option value="5">C5</option><option value="6">C6</option>
                  <option value="7">D7</option><option value="8">E8</option><option value="9">F9</option>
                </select>
                <button type="button" className="structured-remove" onClick={() => removeSubject(index)}>×</button>
              </div>
            ))}
          </div>

          <label>
            Notes
            <textarea rows="3" value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} placeholder="Example: Faculty-approved requirements for BSc Electrical Engineering."/>
          </label>

          <button type="submit" className="primary-action" disabled={!!busy}>
            <CheckCircle2 size={17}/> {form.id ? "Update Rule" : "Save Rule"}
          </button>
        </form>

        <section className="admission-subcard eligibility-rule-list">
          <div className="section-title"><div><h3>Configured rules</h3><p>Cycle-specific rules override the programme default rule.</p></div></div>
          {(data.eligibilityRules || []).map((rule) => {
            const required = (rule.subjects || []).filter((s) => s.subject_group === "required");
            const electives = (rule.subjects || []).filter((s) => s.subject_group === "elective_pool");
            const usesAnyElectiveFallback = Number(rule.minimum_elective_passes || 0) > 0 && electives.length === 0;
            return <button type="button" className="eligibility-rule-card" key={rule.id} onClick={() => editRule(rule)}>
              <div><strong>{rule.programme?.code} — {rule.programme?.name}</strong><span>{rule.admission_cycle?.name || "Default for all cycles"} • {rule.qualification_type}</span></div>
              <div className="eligibility-rule-card-meta"><span>{required.length} required</span><span>{usesAnyElectiveFallback ? `Best ${rule.minimum_elective_passes} other WASSCE subjects` : `Choose ${rule.minimum_elective_passes} of ${electives.length} electives`}</span><span>Aggregate ≤ {rule.max_aggregate ?? "—"}</span></div>
              {usesAnyElectiveFallback ? <div className="form-note">No elective pool is configured. UniMIS will therefore use the applicant's best passing non-required WASSCE subjects for the elective count and aggregate.</div> : null}
            </button>;
          })}
          {!data.eligibilityRules?.length && <div className="table-empty">No programme eligibility rules configured yet.</div>}
        </section>
      </div>
    </div>
  );
}


function EligibilityRegisterWorkspace({data,institutionId,setSelectedApplicationId,setSelectedApplicantId,setActiveTab}){
  const [cycleId,setCycleId]=useState("");
  const [statusFilter,setStatusFilter]=useState("all");
  const [query,setQuery]=useState("");
  const [rows,setRows]=useState([]);
  const [loading,setLoading]=useState(false);
  const [loadError,setLoadError]=useState("");

  const loadRegister=useCallback(async()=>{
    if(!institutionId)return;
    setLoading(true);setLoadError("");
    const result=await loadAdmissionsEligibilityRegister(institutionId,cycleId||null);
    if(result.error){setRows([]);setLoadError(result.error.message);}else setRows(result.data||[]);
    setLoading(false);
  },[institutionId,cycleId]);

  useEffect(()=>{loadRegister();},[loadRegister]);

  const allowedApplicationIds=useMemo(()=>new Set((data.applications||[]).map(a=>a.id)),[data.applications]);
  const filtered=useMemo(()=>rows.filter(row=>{
    if(!allowedApplicationIds.has(row.application_id))return false;
    if(statusFilter!=="all"&&row.eligibility_status!==statusFilter)return false;
    const hay=`${row.application_number||""} ${row.applicant_name||""} ${row.programme_code||""} ${row.programme_name||""}`.toLowerCase();
    return hay.includes(query.trim().toLowerCase());
  }),[rows,statusFilter,query,allowedApplicationIds]);

  const processingRows=useMemo(()=>rows.filter(r=>allowedApplicationIds.has(r.application_id)),[rows,allowedApplicationIds]);
  const counts=useMemo(()=>({
    eligible:processingRows.filter(r=>r.eligibility_status==="eligible").length,
    not_eligible:processingRows.filter(r=>r.eligibility_status==="not_eligible").length,
    incomplete:processingRows.filter(r=>r.eligibility_status==="incomplete").length,
    not_configured:processingRows.filter(r=>r.eligibility_status==="not_configured").length,
  }),[processingRows]);

  function exportCsv(){
    downloadCsvFile(`unimis-eligibility-register-${new Date().toISOString().slice(0,10)}.csv`,
      ["Application","Applicant","Cycle","Choice","Programme","Eligibility","Aggregate","Max Aggregate","Result Verified","Application Status","Reason"],
      filtered.map(r=>[r.application_number,r.applicant_name,r.admission_cycle_name,r.choice_order,`${r.programme_code} — ${r.programme_name}`,r.eligibility_status,r.aggregate??"",r.max_aggregate??"",r.qualification_verified?"Yes":"No",r.application_status,r.message||""]));
  }
  function printReport(){
    printHtmlReport("UniMIS Automatic Eligibility Register",`${filtered.length} programme-choice assessment(s)`,
      ["Application","Applicant","Cycle","Choice","Programme","Eligibility","Aggregate","Verified"],
      filtered.map(r=>[r.application_number,r.applicant_name,r.admission_cycle_name,r.choice_order,`${r.programme_code} — ${r.programme_name}`,r.eligibility_status,r.aggregate==null?"—":`${r.aggregate}/${r.max_aggregate??"—"}`,r.qualification_verified?"Yes":"No"]),
      `<div class="summary"><div><strong>Eligible</strong><br>${counts.eligible}</div><div><strong>Not eligible</strong><br>${counts.not_eligible}</div><div><strong>Incomplete</strong><br>${counts.incomplete}</div><div><strong>Rules missing</strong><br>${counts.not_configured}</div></div>`);
  }
  function openReview(row){setSelectedApplicationId(row.application_id);setSelectedApplicantId(row.applicant_id);setActiveTab("review");}

  return <div className="eligibility-register-workspace">
    <section className="admission-subcard">
      <div className="section-title"><div><h2>Automatic Eligibility Register</h2><p>UniMIS evaluates every applicant against each selected programme using the rules under Setup → Eligibility Rules. Officers review exceptions instead of calculating grades manually.</p></div><div className="report-actions"><button type="button" className="secondary-button" onClick={loadRegister}><RefreshCw size={16}/> Refresh</button><button type="button" className="secondary-button" onClick={exportCsv}><FileSpreadsheet size={16}/> Export CSV</button><button type="button" className="secondary-button" onClick={printReport}><Printer size={16}/> Print / Save PDF</button></div></div>
      <div className="eligibility-register-summary"><div className="eligible"><span>Eligible</span><strong>{counts.eligible}</strong></div><div className="not-eligible"><span>Not eligible</span><strong>{counts.not_eligible}</strong></div><div><span>Incomplete</span><strong>{counts.incomplete}</strong></div><div><span>Rules missing</span><strong>{counts.not_configured}</strong></div></div>
      <div className="verification-filters"><label>Admission cycle<select value={cycleId} onChange={e=>setCycleId(e.target.value)}><option value="">All cycles</option>{data.cycles.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label><label>Eligibility<select value={statusFilter} onChange={e=>setStatusFilter(e.target.value)}><option value="all">All results</option><option value="eligible">Eligible</option><option value="not_eligible">Not eligible</option><option value="incomplete">Incomplete</option><option value="not_configured">Rule not configured</option></select></label><label>Search<input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Applicant, application, programme..."/></label></div>
      {loadError&&<div className="status-message error">{loadError}</div>}
    </section>
    <div className="responsive-table"><table className="academic-table admissions-detail-table eligibility-register-table"><thead><tr><th>Applicant</th><th>Programme choice</th><th>Eligibility</th><th>Aggregate</th><th>Result source</th><th>Reason / Action</th></tr></thead><tbody>
      {filtered.map((row,i)=><tr key={`${row.application_id}-${row.programme_id}-${i}`}><td><strong>{row.applicant_name}</strong><span className="table-subtext">{row.application_number} • {row.admission_cycle_name}</span></td><td><strong>Choice {row.choice_order}: {row.programme_code}</strong><span className="table-subtext">{row.programme_name}</span></td><td><span className={`eligibility-status ${row.eligibility_status}`}>{String(row.eligibility_status||"").replaceAll("_"," ")}</span></td><td>{row.aggregate==null?"—":`${row.aggregate} / ${row.max_aggregate??"—"}`}</td><td>{row.qualification_verified?<span className="status-pill verified">WAEC/result verified</span>:<span className="status-pill pending">Provisional</span>}</td><td><div className="eligibility-register-action"><span>{row.message||"—"}</span><button type="button" className="table-action" onClick={()=>openReview(row)}><ClipboardCheck size={14}/> Review</button></div></td></tr>)}
      {!filtered.length&&<tr><td colSpan="6" className="table-empty">{loading?"Calculating eligibility…":"No eligibility rows match the current filters."}</td></tr>}
    </tbody></table></div>
    <div className="form-note">An <strong>Eligible</strong> result means the entered grades satisfy the configured academic rule. A provisional result still requires official result verification before final admission approval.</div>
  </div>;
}


function AdmissionsApprovalWorkspace({ data, refresh, busy, setBusy, setMessage, setError, confirmAction }) {
  const [selectedId, setSelectedId] = useState("");
  const [recommendation, setRecommendation] = useState("recommend_offer");
  const [programmeId, setProgrammeId] = useState("");
  const [comments, setComments] = useState("");
  const [conditions, setConditions] = useState("");
  const [expiresAt, setExpiresAt] = useState("");
  const [approvalFeedback, setApprovalFeedback] = useState(null);
  const [recommendationSubmittedLocal, setRecommendationSubmittedLocal] = useState(false);
  const [approvalCompletedLocal, setApprovalCompletedLocal] = useState(false);

  const reviewedApplications = useMemo(
    () => data.applications.filter((app) => Boolean(app.reviewed_at) && Boolean(app.submitted_at)),
    [data.applications]
  );

  const application =
    reviewedApplications.find((app) => app.id === selectedId) ||
    reviewedApplications[0] ||
    null;

  useEffect(() => {
    if (!selectedId && reviewedApplications[0]?.id) {
      setSelectedId(reviewedApplications[0].id);
    }
  }, [selectedId, reviewedApplications]);

  useEffect(() => {
    setProgrammeId(application?.choices?.[0]?.programme?.id || "");
    setComments("");
    setConditions("");
    setExpiresAt("");
    setApprovalFeedback(null);
    setRecommendationSubmittedLocal(false);
    setApprovalCompletedLocal(false);
  }, [application?.id]);

  const reviews = application
    ? (data.reviews || []).filter((r) => r.application_id === application.id)
    : [];

  const latestRecommendation = [...reviews]
    .filter((r) => r.review_stage === "recommendation" && r.action === "submitted")
    .sort((x,y) => new Date(y.created_at) - new Date(x.created_at))[0];

  const latestApproval = [...reviews]
    .filter((r) => r.review_stage === "approval")
    .sort((x,y) => new Date(y.created_at) - new Date(x.created_at))[0];

  const offers = application
    ? (data.offers || []).filter((o) => o.application_id === application.id)
    : [];
  const activeOffer = offers.find((o) => ["pending","accepted"].includes(o.response_status));
  const recommendationAlreadySubmitted = Boolean(latestRecommendation) || recommendationSubmittedLocal;
  const approvalAlreadyCompleted = Boolean(activeOffer) || Boolean(latestApproval?.action === "approved_offer") || approvalCompletedLocal;

  const wassce = application
    ? data.qualifications.filter((q) =>
        q.applicant_id === application.applicant_id &&
        (q.qualification_type || "").toUpperCase() === "WASSCE" &&
        (data.subjectResults || []).some((sr) => sr.qualification_id === q.id)
      )
    : [];

  const waecVerified =
    !wassce.length ||
    wassce.every((q) =>
      q.verification_status === "verified" &&
      ["waec_portal","waec_bulk","waec_api"].includes(
        (q.verification_source || "").toLowerCase()
      )
    );

  async function submitRecommendation() {
    if (!application || recommendationAlreadySubmitted) return;

    setBusy(`recommend-${application.id}`);
    setApprovalFeedback(null);

    const result = await submitAdmissionRecommendation({
      applicationId: application.id,
      programmeId,
      recommendation,
      comments,
    });

    if (result.error) {
      setApprovalFeedback({type:"error", text:result.error.message});
      setBusy("");
    } else {
      setRecommendationSubmittedLocal(true);
      setApprovalFeedback({type:"success", text:"Recommendation submitted successfully. It is now locked and ready for authorized approval."});
      setBusy("");
      Promise.resolve(refresh()).catch(err => console.error("Approval workspace refresh failed", err));
    }
  }

  async function approve(action) {
    if (!application) return;
    if (action === "approve_offer" && approvalAlreadyCompleted) return;
    if (!(await confirmAction({
      title: action==="approve_offer" ? "Approve admission offer?" : "Confirm admissions decision?",
      message: action==="approve_offer" ? "Approve this recommendation and create the admission offer?" : `Record decision: ${action.replaceAll("_"," ")}?`,
      confirmLabel: action==="approve_offer" ? "Approve & create offer" : "Confirm",
      tone: action==="reject" ? "danger" : "primary"
    }))) return;

    setBusy(`approval-${application.id}`);
    setApprovalFeedback(null);

    const result = await approveAdmissionRecommendation({
      applicationId: application.id,
      action,
      programmeId: action === "approve_offer" ? programmeId : null,
      comments,
      conditions: action === "approve_offer" ? conditions : null,
      expiresAt:
        action === "approve_offer" && expiresAt
          ? new Date(expiresAt).toISOString()
          : null,
    });

    if (result.error) {
      setApprovalFeedback({type:"error", text:result.error.message});
      setBusy("");
    } else {
      if (action === "approve_offer") {
        setApprovalCompletedLocal(true);
        const offerNo = result.data?.offer_number ? ` Offer ${result.data.offer_number} was created.` : "";
        setApprovalFeedback({type:"success", text:`Admission approved successfully.${offerNo} The approval action is now locked.`});
      } else {
        setApprovalFeedback({type:"success", text:`Admissions decision recorded: ${action.replaceAll("_"," ")}.`});
      }
      setBusy("");
      Promise.resolve(refresh()).catch(err => console.error("Approval refresh failed", err));
    }
  }

  return (
    <div className="approval-workspace">
      <div className="section-title">
        <div>
          <h2>Recommendation, Approval & Offers</h2>
          <p>
            Recommendation and final approval are recorded separately.
            WASSCE applicants must pass official WAEC verification first.
          </p>
        </div>
      </div>

      <div className="approval-layout">
        <aside className="approval-case-list">
          <div className="approval-list-head">
            <strong>Reviewed applications</strong>
            <span>{reviewedApplications.length}</span>
          </div>

          {reviewedApplications.map((app) => {
            const rec = (data.reviews || []).find(
              (r) =>
                r.application_id === app.id &&
                r.review_stage === "recommendation" &&
                r.action === "submitted"
            );
            const offer = (data.offers || []).find(
              (o) => o.application_id === app.id
            );

            return (
              <button
                type="button"
                key={app.id}
                className={`approval-case ${application?.id === app.id ? "active" : ""}`}
                onClick={() => setSelectedId(app.id)}
              >
                <strong>{app.application_number}</strong>
                <span>{applicantName(app.applicant)}</span>
                <small>
                  {offer
                    ? "Offer created"
                    : rec
                    ? "Awaiting approval"
                    : "Awaiting recommendation"}
                </small>
              </button>
            );
          })}

          {!reviewedApplications.length && (
            <div className="table-empty">
              No completed reviews are ready for recommendation.
            </div>
          )}
        </aside>

        <section className="approval-detail">
          {!application ? (
            <div className="table-empty">
              Complete an application review first.
            </div>
          ) : (
            <>
              <div className="review-summary-grid">
                <div>
                  <span>Applicant</span>
                  <strong>{applicantName(application.applicant)}</strong>
                </div>
                <div>
                  <span>Application</span>
                  <strong>{application.application_number}</strong>
                </div>
                <div>
                  <span>Current status</span>
                  <strong>{application.decision_status || "under_review"}</strong>
                </div>
                <div>
                  <span>WAEC status</span>
                  <strong>
                    {waecVerified
                      ? "Verified / not applicable"
                      : "Verification required"}
                  </strong>
                </div>
              </div>

              <div className={`approval-gate ${waecVerified ? "ready" : "blocked"}`}>
                {waecVerified ? <BadgeCheck size={19}/> : <ShieldCheck size={19}/>}
                <div>
                  <strong>
                    {waecVerified
                      ? "Verification gate passed"
                      : "WAEC verification gate"}
                  </strong>
                  <span>
                    {waecVerified
                      ? "This application may proceed to recommendation."
                      : "Record official WAEC verification first."}
                  </span>
                </div>
              </div>

              <section className="admission-subcard">
                <h3>1. Officer Recommendation</h3>

                <div className="form-grid">
                  <label>
                    Recommendation
                    <select
                      value={recommendation}
                      onChange={(e) => setRecommendation(e.target.value)}
                      disabled={recommendationAlreadySubmitted}
                    >
                      <option value="recommend_offer">Recommend for admission</option>
                      <option value="waitlist">Recommend waitlist</option>
                      <option value="recommend_reject">Recommend rejection</option>
                      <option value="hold">Hold for clarification</option>
                    </select>
                  </label>

                  <label>
                    Programme
                    <select
                      value={programmeId}
                      onChange={(e) => setProgrammeId(e.target.value)}
                      disabled={recommendationAlreadySubmitted || approvalAlreadyCompleted}
                    >
                      <option value="">Select programme…</option>
                      {(application.choices || []).map((choice) => (
                        <option
                          key={choice.id}
                          value={choice.programme?.id || ""}
                        >
                          Choice {choice.choice_order}: {choice.programme?.code} — {choice.programme?.name}
                        </option>
                      ))}
                    </select>
                  </label>
                </div>

                <label>
                  Recommendation notes
                  <textarea
                    rows="3"
                    value={comments}
                    onChange={(e) => setComments(e.target.value)}
                    placeholder="Reason for recommendation, exception or professional judgement…"
                    disabled={recommendationAlreadySubmitted || approvalAlreadyCompleted}
                  />
                </label>

                <button
                  type="button"
                  className="primary-action"
                  disabled={!!busy || !waecVerified || recommendationAlreadySubmitted}
                  onClick={submitRecommendation}
                >
                  <ClipboardCheck size={16}/>
                  {recommendationAlreadySubmitted
                    ? "Recommendation Submitted"
                    : busy===`recommend-${application.id}`
                    ? "Submitting Recommendation..."
                    : "Submit Recommendation"}
                </button>

                {latestRecommendation && (
                  <div className="decision-history-card">
                    <strong>
                      Latest:{" "}
                      {String(latestRecommendation.recommendation || "").replaceAll("_"," ")}
                    </strong>
                    <span>{latestRecommendation.comments || "No comments"}</span>
                  </div>
                )}
              </section>

              <section className="admission-subcard">
                <h3>2. Authorized Approval</h3>

                {!latestRecommendation ? (
                  <div className="review-alert">
                    <span>Submit a recommendation before final approval.</span>
                  </div>
                ) : (
                  <>
                    <label>
                      Offer conditions
                      <textarea
                        rows="2"
                        value={conditions}
                        onChange={(e) => setConditions(e.target.value)}
                        placeholder="Optional conditions visible to the applicant…"
                        disabled={approvalAlreadyCompleted}
                      />
                    </label>

                    <label>
                      Offer expiry
                      <input
                        type="datetime-local"
                        value={expiresAt}
                        onChange={(e) => setExpiresAt(e.target.value)}
                        disabled={approvalAlreadyCompleted}
                      />
                    </label>

                    <div className="approval-actions">
                      <button
                        type="button"
                        className="primary-action"
                        disabled={
                          !!busy ||
                          !programmeId ||
                          approvalAlreadyCompleted
                        }
                        onClick={() => approve("approve_offer")}
                      >
                        <BadgeCheck size={16}/>
                        {approvalAlreadyCompleted
                          ? "Offer Already Approved"
                          : busy===`approval-${application.id}`
                          ? "Approving & Creating Offer..."
                          : "Approve & Create Offer"}
                      </button>

                      <button
                        type="button"
                        className="secondary-button"
                        disabled={!!busy || approvalAlreadyCompleted}
                        onClick={() => approve("waitlist")}
                      >
                        Waitlist
                      </button>

                      <button
                        type="button"
                        className="secondary-button"
                        disabled={!!busy || approvalAlreadyCompleted}
                        onClick={() => approve("return_for_review")}
                      >
                        Return for Review
                      </button>

                      <button
                        type="button"
                        className="table-action danger"
                        disabled={!!busy || approvalAlreadyCompleted}
                        onClick={() => approve("reject")}
                      >
                        <BadgeX size={15}/>
                        Reject
                      </button>
                    </div>
                  </>
                )}

                {latestApproval && (
                  <div className="decision-history-card">
                    <strong>
                      Latest approval:{" "}
                      {String(latestApproval.action || "").replaceAll("_"," ")}
                    </strong>
                    <span>{latestApproval.comments || "No comments"}</span>
                  </div>
                )}
              </section>

              {approvalFeedback && (
                <div className={`inline-action-feedback approval-inline-feedback ${approvalFeedback.type}`}>
                  <strong>{approvalFeedback.type==="success" ? "✓ Action completed" : "Action could not be completed"}</strong>
                  <span>{approvalFeedback.text}</span>
                </div>
              )}

              {!!offers.length && (
                <section className="admission-subcard">
                  <h3>Admission Offer</h3>
                  {offers.map((offer) => (
                    <div className="offer-admin-card" key={offer.id}>
                      <div>
                        <strong>{offer.offer_number}</strong>
                        <span>
                          {offer.programme?.code} — {offer.programme?.name}
                        </span>
                      </div>
                      <span className={`status-pill ${offer.response_status || "pending"}`}>
                        {offer.response_status || "pending"}
                      </span>
                    </div>
                  ))}
                </section>
              )}
            </>
          )}
        </section>
      </div>
    </div>
  );
}

function ApplicationReviewWorkspace({
  data,
  busy,
  setBusy,
  setMessage = () => {},
  setError = () => {},
  refresh = async () => {},
}) {
  const [selectedApplicationId, setSelectedApplicationId] = useState("");
  const [queueFilter, setQueueFilter] = useState("ready");
  const [search, setSearch] = useState("");
  const [reviewNotes, setReviewNotes] = useState("");
  const [recommendation, setRecommendation] = useState("recommend_offer");
  const [recommendationNotes, setRecommendationNotes] = useState("");
  const [reviewCompletedId, setReviewCompletedId] = useState("");
  const [recommendationSubmittedId, setRecommendationSubmittedId] = useState("");
  const [reviewActionFeedback, setReviewActionFeedback] = useState(null);

  const applicantById = useMemo(() => new Map((data.applicants || []).map(x => [x.id, x])), [data.applicants]);
  const programmeById = useMemo(() => new Map((data.programmes || []).map(x => [x.id, x])), [data.programmes]);
  const [applicantFilterId, setApplicantFilterId] = useState("all");

  function resolvedApplicant(app) {
    return app?.applicant || applicantById.get(app?.applicant_id) || null;
  }

  function appName(app) {
    const a = resolvedApplicant(app);
    return [a?.first_name, a?.middle_name, a?.last_name].filter(Boolean).join(" ") || "Unnamed applicant";
  }

  function firstChoice(app) {
    // Applications are loaded with nested application_choices + programme.
    // Use the nested relationship first; fall back to any legacy flat collection.
    const nested = Array.isArray(app?.choices) ? app.choices : [];
    const legacy = Array.isArray(data.choices)
      ? data.choices.filter(c => c.application_id === app.id)
      : [];
    return [...nested, ...legacy]
      .sort((a,b) => Number(a.choice_order || 99) - Number(b.choice_order || 99))[0] || null;
  }

  function resolvedProgramme(choice) {
    return choice?.programme || programmeById.get(choice?.programme_id) || null;
  }

  function requiredDocsFor(app) {
    const choice = firstChoice(app);
    return (data.documentRequirements || []).filter(r => {
      if (r.is_active === false || r.is_required === false) return false;
      if (r.admission_cycle_id && r.admission_cycle_id !== app.admission_cycle_id) return false;
      const choiceProgrammeId = choice?.programme_id || choice?.programme?.id || null;
      if (r.programme_id && r.programme_id !== choiceProgrammeId) return false;
      const cat = String(r.applicant_category || "both").toLowerCase();
      const level = String(r.admission_level || "both").toLowerCase();
      const appCat = String(app.applicant?.applicant_category || app.applicant_category || "local").toLowerCase();
      const appLevel = String(app.admission_cycle?.admission_level || app.admission_level || "undergraduate").toLowerCase();
      return (cat === "both" || cat === appCat) && (level === "both" || level === appLevel);
    });
  }

  function statusFor(app) {
    const applicant = resolvedApplicant(app);
    const choice = firstChoice(app);
    const quals = (data.qualifications || []).filter(q => q.applicant_id === app.applicant_id);
    const wassce = quals.filter(q => String(q.qualification_type || "").toUpperCase() === "WASSCE");
    const docs = (data.documents || []).filter(d => d.application_id === app.id);
    const reqs = requiredDocsFor(app);
    const verifiedReqs = reqs.filter(r => docs.some(d =>
      String(d.document_type || "").toLowerCase() === String(r.document_type || "").toLowerCase() &&
      String(d.verification_status || "").toLowerCase() === "verified"
    ));
    const feeRequired = app.admission_cycle?.payment_required !== false;
    const feeOk = !feeRequired || ["paid","verified","not_required"].includes(String(app.payment_status || "").toLowerCase());
    const submitted = Boolean(app.submitted_at);
    const programmeOk = Boolean(choice?.programme_id || choice?.programme?.id);
    const qualificationOk = quals.length > 0;
    const docsUploaded = reqs.every(r => docs.some(d => String(d.document_type || "").toLowerCase() === String(r.document_type || "").toLowerCase()));
    const docsVerified = reqs.every(r => docs.some(d =>
      String(d.document_type || "").toLowerCase() === String(r.document_type || "").toLowerCase() &&
      String(d.verification_status || "").toLowerCase() === "verified"
    ));
    const waecMismatch = wassce.some(q => String(q.verification_status || "").toLowerCase() === "mismatch");
    const waecPending = wassce.length > 0 && wassce.some(q =>
      String(q.verification_status || "").toLowerCase() !== "verified" ||
      !["waec_portal","waec_bulk","waec_api"].includes(String(q.verification_source || "").toLowerCase())
    );
    const waecOk = wassce.length === 0 || (!waecMismatch && !waecPending);
    const ready = submitted && feeOk && programmeOk && qualificationOk && docsUploaded && docsVerified && waecOk;

    const blockers = [];
    if (!submitted) blockers.push("Application not submitted");
    if (!feeOk) blockers.push("Application fee not verified");
    if (!programmeOk) blockers.push("Programme choice missing");
    if (!qualificationOk) blockers.push("Qualification missing");
    if (!docsUploaded) blockers.push("Required documents missing");
    else if (!docsVerified) blockers.push("Required documents not fully verified");
    if (waecMismatch) blockers.push("WAEC result mismatch");
    else if (waecPending) blockers.push("WAEC verification incomplete");

    const latestReview = (data.reviews || [])
      .filter(r => r.application_id === app.id)
      .sort((a,b) => new Date(b.created_at || 0) - new Date(a.created_at || 0))[0];

    return {
      applicant, choice, programme: resolvedProgramme(choice),
      quals, wassce, reqs, docs, verifiedReqs, feeOk, submitted, programmeOk,
      qualificationOk, docsUploaded, docsVerified, waecOk, waecMismatch, waecPending,
      ready, blockers, latestReview
    };
  }

  const queue = useMemo(() => (data.applications || []).map(app => ({app, ...statusFor(app)})), [data]);
  const filteredQueue = queue.filter(row => {
    const q = search.trim().toLowerCase();
    const matchesSearch = !q || `${row.app.application_number || ""} ${appName(row.app)} ${row.programme?.name || ""}`.toLowerCase().includes(q);
    const matchesApplicant = applicantFilterId === "all" || row.app.applicant_id === applicantFilterId;
    const reviewed = Boolean(row.latestReview);
    if (!matchesSearch || !matchesApplicant) return false;
    if (queueFilter === "ready") return row.ready && !reviewed;
    if (queueFilter === "blocked") return !row.ready;
    if (queueFilter === "reviewed") return reviewed;
    return true;
  });

  const readyCount = queue.filter(r => r.ready && !r.latestReview).length;
  const blockedCount = queue.filter(r => !r.ready).length;
  const reviewedCount = queue.filter(r => Boolean(r.latestReview)).length;

  const selectedRow = queue.find(r => r.app.id === selectedApplicationId) || null;
  useEffect(() => { setReviewActionFeedback(null); }, [selectedApplicationId]);
  const reviewCompleted = Boolean(selectedRow && (reviewCompletedId === selectedRow.app.id || selectedRow.latestReview));
  const recommendationSubmitted = Boolean(selectedRow && recommendationSubmittedId === selectedRow.app.id);

  async function completeReview() {
    if (!selectedRow?.ready) {
      setError("This application is not ready for review. Resolve all pre-screening requirements first.");
      return;
    }
    setBusy("complete-review");
    setError("");
    const result = await completeApplicationReview(
      selectedRow.app.id,
      reviewNotes || "Admissions review completed."
    );
    if (result.error) {
      setReviewActionFeedback({type:"error", text:result.error.message});
      setBusy("");
    } else {
      setReviewCompletedId(selectedRow.app.id);
      setReviewActionFeedback({type:"success", text:"Officer review completed. Step 2 is now available."});
      setBusy("");
      Promise.resolve(refresh()).catch(err => console.error("Review refresh failed", err));
    }
  }

  async function submitRecommendation() {
    if (!selectedRow?.ready) {
      setError("Recommendation is blocked until all pre-screening requirements are satisfied.");
      return;
    }
    if (!reviewCompleted) {
      setError("Complete the officer review before submitting a recommendation.");
      return;
    }
    setBusy("recommendation");
    setError("");
    const result = await submitAdmissionRecommendation({
      applicationId: selectedRow.app.id,
      recommendation,
      programmeId: selectedRow.choice?.programme_id || selectedRow.choice?.programme?.id,
      comments: recommendationNotes || null
    });
    if (result.error) {
      setReviewActionFeedback({type:"error", text:result.error.message});
      setBusy("");
    } else {
      setRecommendationSubmittedId(selectedRow.app.id);
      setReviewActionFeedback({type:"success", text:"Recommendation submitted successfully. This application is now awaiting authorized approval."});
      setRecommendationNotes("");
      setBusy("");
      Promise.resolve(refresh()).catch(err => console.error("Recommendation refresh failed", err));
    }
  }

  return <div className="review-queue-workspace">
    <div className="section-title">
      <div>
        <h2>Review & Recommendation</h2>
        <p>UniMIS automatically groups submitted applications by readiness. Officers review exceptions rather than manually discovering eligible applications.</p>
      </div>
    </div>

    <div className="review-queue-summary">
      <button type="button" className={queueFilter==="ready"?"active":""} onClick={()=>{setQueueFilter("ready");setSelectedApplicationId("");}}>
        <span>Ready for Review</span><strong>{readyCount}</strong>
      </button>
      <button type="button" className={queueFilter==="blocked"?"active blocked":""} onClick={()=>{setQueueFilter("blocked");setSelectedApplicationId("");}}>
        <span>Blocked / Attention</span><strong>{blockedCount}</strong>
      </button>
      <button type="button" className={queueFilter==="reviewed"?"active":""} onClick={()=>{setQueueFilter("reviewed");setSelectedApplicationId("");}}>
        <span>Reviewed</span><strong>{reviewedCount}</strong>
      </button>
      <button type="button" className={queueFilter==="all"?"active":""} onClick={()=>{setQueueFilter("all");setSelectedApplicationId("");}}>
        <span>All Processing</span><strong>{queue.length}</strong>
      </button>
    </div>

    <div className="report-filter-row review-filter-row">
      <select value={applicantFilterId} onChange={e=>setApplicantFilterId(e.target.value)} aria-label="Filter by applicant">
        <option value="all">All applicants</option>
        {queue
          .slice()
          .sort((a,b)=>appName(a.app).localeCompare(appName(b.app)))
          .map(row=><option key={row.app.id} value={row.app.applicant_id}>{appName(row.app)} — {row.app.application_number}</option>)}
      </select>
      <input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search application, applicant or programme..." />
    </div>

    <div className="responsive-table review-queue-table">
      <table className="academic-table">
        <thead><tr>
          <th>Application</th><th>Applicant</th><th>Programme</th><th>Fee</th>
          <th>Documents</th><th>WAEC</th><th>Review state</th><th>Action</th>
        </tr></thead>
        <tbody>
          {filteredQueue.map(row => <tr key={row.app.id}>
            <td><strong>{row.app.application_number || "—"}</strong></td>
            <td>{appName(row.app)}</td>
            <td>{row.programme?.name || "—"}</td>
            <td><span className={`status-pill ${row.feeOk?"verified":"mismatch"}`}>{row.feeOk?"Verified":"Pending"}</span></td>
            <td><strong>{row.verifiedReqs.length}/{row.reqs.length}</strong><span className="table-subtext">{row.docsVerified?"Verified":"Attention"}</span></td>
            <td>
              <span className={`status-pill ${row.waecOk?"verified":row.waecMismatch?"mismatch":"unverified"}`}>
                {row.waecOk ? (row.wassce.length>1?`${row.wassce.length}/${row.wassce.length} verified`:"Verified") : row.waecMismatch?"Mismatch":"Pending"}
              </span>
            </td>
            <td>
              {row.ready
                ? <span className="status-pill verified">{row.latestReview?"Reviewed":"Ready"}</span>
                : <span className="status-pill mismatch">Blocked</span>}
              {!row.ready && <span className="table-subtext">{row.blockers.join(" • ")}</span>}
            </td>
            <td><button type="button" className="table-action" onClick={()=>setSelectedApplicationId(row.app.id)}>{row.ready?"Review":"Inspect"}</button></td>
          </tr>)}
          {!filteredQueue.length && <tr><td colSpan="8" className="table-empty">No applications in this queue.</td></tr>}
        </tbody>
      </table>
    </div>

    {selectedRow && <section className="admission-subcard review-detail-panel">
      <div className="section-title">
        <div><h3>{selectedRow.app.application_number} — {appName(selectedRow.app)}</h3><p>{selectedRow.programme?.name || "No programme choice"}</p></div>
        <button type="button" className="secondary-button" onClick={()=>setSelectedApplicationId("")}>Close</button>
      </div>

      <div className="review-detail-summary">
        <div><span>Applicant</span><strong>{appName(selectedRow.app)}</strong></div>
        <div><span>Programme</span><strong>{selectedRow.programme?.name || "—"}</strong></div>
        <div><span>Qualifications</span><strong>{selectedRow.quals.length}</strong></div>
        <div><span>Verified documents</span><strong>{selectedRow.verifiedReqs.length}/{selectedRow.reqs.length}</strong></div>
      </div>

      <div className={`review-prescreen ${selectedRow.ready?"ready":"blocked"}`}>
        <div className="review-prescreen-heading">
          <div><h3>System Pre-screening</h3><p>All formal admission requirements are checked before an officer can complete review or recommend a decision.</p></div>
          <span className={`status-pill ${selectedRow.ready?"verified":"mismatch"}`}>{selectedRow.ready?"Ready for Review":"Attention Required"}</span>
        </div>
        <div className="review-check-grid">
          {[
            ["Application submitted",selectedRow.submitted],
            ["Application fee verified",selectedRow.feeOk],
            ["Programme choice recorded",selectedRow.programmeOk],
            ["Qualification recorded",selectedRow.qualificationOk],
            ["Required documents uploaded",selectedRow.docsUploaded],
            ["Required documents verified",selectedRow.docsVerified],
            ["Structured examination results verified",selectedRow.waecOk]
          ].map(([label,ok])=><div key={label} className={ok?"pass":"fail"}><span>{ok?"✓":"✕"}</span>{label}</div>)}
        </div>
        {!selectedRow.ready && <div className="review-blocker-box"><strong>Resolve before review:</strong> {selectedRow.blockers.join(" • ")}</div>}
      </div>

      <div className="review-evidence-grid">
        <section>
          <h4>Qualifications & WAEC evidence</h4>
          {selectedRow.quals.map(q=><div className="review-evidence-row" key={q.id}>
            <div><strong>{q.qualification_type}</strong><span>{q.index_number || "No index"} • {q.completion_year || "—"} • {q.exam_sitting || "—"}</span></div>
            <span className={`status-pill ${q.verification_status==="verified"?"verified":q.verification_status==="mismatch"?"mismatch":"unverified"}`}>{q.verification_status || "unverified"}</span>
          </div>)}
        </section>
        <section>
          <h4>Required documents</h4>
          {selectedRow.reqs.map(r=>{
            const d=selectedRow.docs.find(x=>String(x.document_type||"").toLowerCase()===String(r.document_type||"").toLowerCase());
            return <div className="review-evidence-row" key={r.id || r.document_type}>
              <div><strong>{r.display_name || r.document_type}</strong><span>{d?.file_name || "Not uploaded"}</span></div>
              <span className={`status-pill ${d?.verification_status==="verified"?"verified":"unverified"}`}>{d?.verification_status || "missing"}</span>
            </div>;
          })}
        </section>
      </div>

      {selectedRow.ready && <section className="review-decision-workflow">
        <div className="review-step-header">
          <div className={`review-step ${reviewCompleted ? "done" : "current"}`}><span>1</span><div><strong>Officer Review</strong><small>{reviewCompleted ? "Completed" : "Review evidence and sign off"}</small></div></div>
          <div className={`review-step ${recommendationSubmitted ? "done" : reviewCompleted ? "current" : ""}`}><span>2</span><div><strong>Recommendation</strong><small>{recommendationSubmitted ? "Submitted" : "Submit decision for approval"}</small></div></div>
        </div>
        <section className={`review-action-card ${reviewCompleted ? "completed" : ""}`}>
          <div className="review-action-heading"><h4>Step 1 — Complete Officer Review</h4>{reviewCompleted && <span className="status-pill verified">✓ Review Completed</span>}</div>
          <textarea rows="3" value={reviewNotes} onChange={e=>setReviewNotes(e.target.value)} placeholder="Review notes, authenticity observations or exceptions..." disabled={reviewCompleted}/>
          {!reviewCompleted
            ? <button className="primary-button" type="button" disabled={!!busy} onClick={completeReview}>{busy==="complete-review"?"Completing review...":"Complete Review"}</button>
            : <div className="review-success-message">✓ Officer review saved. Continue directly to Step 2 below.</div>}
        </section>
        <section className={`review-action-card ${!reviewCompleted ? "locked" : ""} ${recommendationSubmitted ? "completed" : ""}`}>
          <div className="review-action-heading"><h4>Step 2 — Recommendation</h4>{recommendationSubmitted && <span className="status-pill verified">✓ Recommendation Submitted</span>}</div>
          {!reviewCompleted && <div className="review-lock-message">Complete Step 1 before submitting a recommendation.</div>}
          <div className="review-recommend-grid">
            <select value={recommendation} onChange={e=>setRecommendation(e.target.value)} disabled={!reviewCompleted||recommendationSubmitted}>
              <option value="recommend_offer">Recommend Offer</option><option value="recommend_reject">Recommend Reject</option><option value="waitlist">Waitlist</option><option value="hold">Hold</option>
            </select>
            <textarea rows="3" value={recommendationNotes} onChange={e=>setRecommendationNotes(e.target.value)} placeholder="Recommendation rationale..." disabled={!reviewCompleted||recommendationSubmitted}/>
          </div>
          {!recommendationSubmitted
            ? <button className="primary-button" type="button" disabled={!!busy||!reviewCompleted} onClick={submitRecommendation}>{busy==="recommendation"?"Submitting recommendation...":"Submit Recommendation"}</button>
            : <div className="review-success-message">✓ Recommendation submitted. This action is now locked to prevent duplicate submission.</div>}
        </section>
        {reviewActionFeedback && <div className={`inline-action-feedback ${reviewActionFeedback.type}`}>{reviewActionFeedback.type==="success"?"✓":"!"} {reviewActionFeedback.text}</div>}
      </section>}
    </section>}
  </div>;
}

function QualificationForm({ form, setForm }) {
  const set = (key) => (e) =>
    setForm({ ...form, [key]: e.target.value });

  return (
    <>
      <div className="form-grid">
        <label>
          Qualification type
          <input
            required
            value={form.qualification_type}
            onChange={set("qualification_type")}
            placeholder="WASSCE, Diploma, HND, Degree..."
          />
        </label>

        <label>
          Examining body
          <input
            value={form.examining_body}
            onChange={set("examining_body")}
            placeholder="WAEC, University..."
          />
        </label>
      </div>

      <label>
        Institution / School
        <input
          value={form.institution_name}
          onChange={set("institution_name")}
        />
      </label>

      <div className="form-grid">
        <label>
          Index / Certificate number
          <input
            value={form.index_number}
            onChange={set("index_number")}
          />
        </label>

        <label>
          Completion year
          <input
            type="number"
            min="1950"
            max="2100"
            value={form.completion_year}
            onChange={set("completion_year")}
          />
        </label>
      </div>

      <label>
        Overall result / classification
        <input
          value={form.overall_result}
          onChange={set("overall_result")}
          placeholder="Aggregate 12, First Class, etc."
        />
      </label>
    </>
  );
}

function DocumentUploadForm({ form, setForm }) {
  return (
    <>
      <label>
        Document type
        <input
          required
          value={form.document_type}
          onChange={(e) =>
            setForm({ ...form, document_type: e.target.value })
          }
          placeholder="Application Form, WASSCE Results, ID, Passport Photo..."
        />
      </label>

      <label>
        File
        <input
          required
          type="file"
          accept=".pdf,.jpg,.jpeg,.png,.webp"
          onChange={(e) =>
            setForm({ ...form, file: e.target.files?.[0] || null })
          }
        />
      </label>

      <div className="form-note">
        This supports both officer-scanned/offline forms and supporting documents.
        The future applicant portal will upload into this same document store.
      </div>
    </>
  );
}


function PaymentSubmissionWorkspace({
  data,
  selectedApplicationId,
  setSelectedApplicationId,
  offlinePayment,
  setOfflinePayment,
  handleRecordOfflinePayment,
  handleVerifyOfflinePayment,
  handleOnlinePayment,
  handleSubmitApplication,
  setActiveTab,
  busy,
}) {
  const [reportStatus, setReportStatus] = useState("verified");
  const [reportCycle, setReportCycle] = useState("all");
  const [reportMethod, setReportMethod] = useState("all");

  const application = data.applications.find((row) => row.id === selectedApplicationId);
  const payments = application ? data.payments.filter((row) => row.application_id === application.id) : [];
  const verifiedPayment = payments.find((row) => row.status === "verified");
  const resolvedFee = resolveApplicationFee(application, data.feeRules, payments);
  const fee = resolvedFee.amount;
  const currency = resolvedFee.currency;

  const applicationMap = useMemo(
    () => Object.fromEntries(data.applications.map((a) => [a.id, a])),
    [data.applications]
  );

  const reportRows = useMemo(() => data.payments.filter((p) => {
    const app = applicationMap[p.application_id];
    if (reportStatus !== "all" && p.status !== reportStatus) return false;
    if (reportCycle !== "all" && app?.admission_cycle_id !== reportCycle) return false;
    if (reportMethod !== "all" && paymentGroupLabel(p) !== reportMethod) return false;
    return true;
  }), [data.payments, applicationMap, reportStatus, reportCycle, reportMethod]);

  const reportTotal = reportRows.reduce((sum, p) => sum + Number(p.amount || 0), 0);
  const groupSummary = Object.entries(reportRows.reduce((acc, p) => {
    const key = paymentGroupLabel(p);
    acc[key] = (acc[key] || 0) + Number(p.amount || 0);
    return acc;
  }, {}));

  const methodOptions = [...new Set(data.payments.map(paymentGroupLabel))].sort();

  function exportCsv() {
    const header = ["Date","Application","Applicant","Cycle","Type","Provider","Reference","Currency","Amount","Status"];
    const rows = reportRows.map((p) => {
      const app = applicationMap[p.application_id];
      return [
        p.verified_at || p.paid_at || p.created_at,
        app?.application_number || "",
        applicantName(app?.applicant),
        app?.admission_cycle?.name || "",
        paymentGroupLabel(p),
        p.provider || "",
        p.provider_reference || "",
        p.currency || "",
        Number(p.amount || 0).toFixed(2),
        p.status || "",
      ];
    });
    const csv = [header,...rows].map((row) => row.map((v) => `"${String(v ?? "").replaceAll('"','""')}"`).join(",")).join("\n");
    const blob = new Blob([csv], {type:"text/csv;charset=utf-8"});
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url; a.download = `unimis-admission-payments-${new Date().toISOString().slice(0,10)}.csv`; a.click();
    URL.revokeObjectURL(url);
  }

  function printReport() {

    const rows = reportRows.map((p) => {
      const app = applicationMap[p.application_id];
      return `<tr><td>${escapeHtml(new Date(p.verified_at || p.paid_at || p.created_at).toLocaleString())}</td><td>${escapeHtml(app?.application_number || "")}</td><td>${escapeHtml(applicantName(app?.applicant))}</td><td>${escapeHtml(paymentGroupLabel(p))}</td><td>${escapeHtml(p.provider || "—")}</td><td>${escapeHtml(p.provider_reference || "—")}</td><td>${escapeHtml(`${p.currency || ""} ${Number(p.amount || 0).toFixed(2)}`)}</td></tr>`;
    }).join("");
    printLegacyDocument122("UniMIS Admissions Report",`<!doctype html><html><head><title>UniMIS Admission Payment Report</title><style>body{font-family:Arial,sans-serif;padding:30px;color:#17233b}h1{color:#123b72;margin-bottom:4px}.meta{color:#667085;margin-bottom:20px}.summary{display:flex;gap:12px;flex-wrap:wrap;margin:18px 0}.summary div{border:1px solid #ddd;border-radius:8px;padding:10px 14px}table{width:100%;border-collapse:collapse;font-size:12px}th,td{border:1px solid #ddd;padding:8px;text-align:left}th{background:#f3f6fa}@media print{button{display:none}}</style></head><body><h1>UniMIS Admission Payment Report</h1><div class="meta">Generated ${escapeHtml(new Date().toLocaleString())}</div><div class="summary"><div><strong>Transactions</strong><br>${reportRows.length}</div><div><strong>Total</strong><br>${escapeHtml(reportRows[0]?.currency || "GHS")} ${reportTotal.toFixed(2)}</div>${groupSummary.map(([g,t])=>`<div><strong>${escapeHtml(g)}</strong><br>${t.toFixed(2)}</div>`).join("")}</div><table><thead><tr><th>Date</th><th>Application</th><th>Applicant</th><th>Type</th><th>Provider</th><th>Reference</th><th>Amount</th></tr></thead><tbody>${rows || '<tr><td colspan="7">No payments</td></tr>'}</tbody></table></body></html>`);
  
  }

  const setOffline = (key) => (e) => setOfflinePayment((current) => ({ ...current, [key]: e.target.value }));

  return (
    <div className="payment-submission-workspace">
      <section className="admission-subcard payment-report-card">
        <div className="section-title">
          <div><h2>Admission Payment Report</h2><p>Institution-wide payment summary. Filter, export CSV, or Print / Save as PDF.</p></div>
          <div className="report-actions">
            <button type="button" className="secondary-button" onClick={exportCsv}><Download size={16}/> Export CSV</button>
            <button type="button" className="secondary-button" onClick={printReport}><FileText size={16}/> Print / Save PDF</button>
          </div>
        </div>
        <div className="payment-report-filters">
          <label>Status<select value={reportStatus} onChange={(e)=>setReportStatus(e.target.value)}><option value="all">All</option><option value="verified">Verified</option><option value="pending">Pending</option><option value="failed">Failed</option><option value="cancelled">Cancelled</option><option value="refunded">Refunded</option></select></label>
          <label>Admission cycle<select value={reportCycle} onChange={(e)=>setReportCycle(e.target.value)}><option value="all">All cycles</option>{data.cycles.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
          <label>Payment type<select value={reportMethod} onChange={(e)=>setReportMethod(e.target.value)}><option value="all">All types</option>{methodOptions.map(m=><option key={m}>{m}</option>)}</select></label>
        </div>
        <div className="payment-report-summary">
          <div><span>Transactions</span><strong>{reportRows.length}</strong></div>
          <div><span>Total</span><strong>{reportRows[0]?.currency || "GHS"} {reportTotal.toFixed(2)}</strong></div>
          {groupSummary.slice(0,4).map(([group,total])=><div key={group}><span>{group}</span><strong>{total.toFixed(2)}</strong></div>)}
        </div>
      </section>

      <div className="admission-record-selector">
        <label>Application<select value={selectedApplicationId} onChange={(e) => setSelectedApplicationId(e.target.value)}><option value="">Select application…</option>{data.applications.map((row)=><option key={row.id} value={row.id}>{row.application_number} — {applicantName(row.applicant)}</option>)}</select></label>
      </div>

      {!application ? <div className="table-empty">Select an application to manage payment and submission.</div> : <>
        <div className="payment-summary-grid">
          <div><span>Applicant</span><strong>{applicantName(application.applicant)}</strong></div>
          <div><span>Application fee</span><strong>{currency} {fee.toFixed(2)}</strong></div>
          <div><span>Payment</span><strong>{verifiedPayment ? "Verified" : fee <= 0 ? "Not required" : "Outstanding"}</strong></div>
          <div><span>Submission</span><strong>{application.submitted_at ? "Submitted" : "Draft"}</strong></div>
        </div>

        {verifiedPayment ? (
          <section className="admission-subcard verified-payment-panel">
            <div className="admission-readonly-status success">
              <CheckCircle2 size={19}/>
              <div>
                <strong>Application Fee Verified</strong>
                <span>{verifiedPayment.currency} {Number(verifiedPayment.amount).toFixed(2)} • {paymentGroupLabel(verifiedPayment)} • {verifiedPayment.provider || "Paystack"}</span>
                {verifiedPayment.provider_reference && <small>Ref: {verifiedPayment.provider_reference}</small>}
              </div>
            </div>
            <p className="form-note">Payment is already verified. Additional Online or Offline payment entry is hidden to prevent duplicate collection.</p>
          </section>
        ) : (
          <div className="payment-method-grid">
            <section className="admission-subcard">
              <div className="payment-card-heading"><CreditCard size={22}/><div><h3>Online Payment</h3><p>Pay securely through Paystack.</p></div></div>
              <button type="button" className="primary-action" disabled={busy === "paystack" || fee <= 0} onClick={() => handleOnlinePayment(application)}>
                <ExternalLink size={17}/> Pay {currency} {fee.toFixed(2)}
              </button>
              <div className="form-note">Paystack checkout is initialized by a Supabase Edge Function. The secret key never enters the React frontend.</div>
            </section>

            <section className="admission-subcard">
              <div className="payment-card-heading"><Banknote size={22}/><div><h3>Offline / Walk-in Payment</h3><p>Record cash, bank transfer or MoMo paid outside the online portal.</p></div></div>
              <div className="payment-form-grid">
                <label>Amount<input type="number" min="0.01" step="0.01" value={offlinePayment.amount} onChange={setOffline("amount")} placeholder={fee ? String(fee) : "0.00"}/></label>
                <label>Method<select value={offlinePayment.payment_method} onChange={setOffline("payment_method")}><option value="cash">Cash</option><option value="bank_transfer">Bank transfer</option><option value="mobile_money">Mobile money</option><option value="other">Other</option></select></label>
                <label>Provider<input value={offlinePayment.provider} onChange={setOffline("provider")} placeholder="MTN, Ecobank, Cash Office..."/></label>
                <label>Reference / receipt no.<input value={offlinePayment.provider_reference} onChange={setOffline("provider_reference")}/></label>
                <label>Paid at<input type="datetime-local" value={offlinePayment.paid_at} onChange={setOffline("paid_at")}/></label>
                <label>Notes<input value={offlinePayment.notes} onChange={setOffline("notes")}/></label>
              </div>
              <button type="button" className="secondary-button" disabled={busy === "offline-payment"} onClick={() => handleRecordOfflinePayment(application, resolvedFee)}>
                <Banknote size={17}/> Record Offline Payment
              </button>
            </section>
          </div>
        )}

        <section className="admission-subcard payment-history-card">
          <div className="section-title"><div><h2>Payment History</h2><p>Online attempts and manually recorded payments for this application.</p></div></div>
          <div className="responsive-table"><table className="academic-table admissions-detail-table"><thead><tr><th>Date</th><th>Channel</th><th>Method</th><th>Reference</th><th>Amount</th><th>Status</th><th>Action</th></tr></thead><tbody>
            {payments.map((payment)=><tr key={payment.id}><td>{new Date(payment.created_at).toLocaleString()}</td><td>{payment.channel}</td><td>{paymentMethodLabel(payment)}</td><td>{payment.provider_reference || "—"}</td><td>{payment.currency} {Number(payment.amount).toFixed(2)}</td><td><span className={`status-pill ${payment.status}`}>{payment.status}</span></td><td>{payment.channel === "offline" && payment.status === "pending" ? <button type="button" className="table-action" disabled={!!busy} onClick={() => handleVerifyOfflinePayment(payment.id)}><CheckCircle2 size={14}/> Verify</button> : "—"}</td></tr>)}
            {!payments.length&&<tr><td colSpan="7" className="table-empty">No payment records yet.</td></tr>}
          </tbody></table></div>
        </section>

        <section className="admission-subcard submission-card">
          <div><h3>Application Submission</h3><p>Submission is allowed when the cycle has no fee or when at least one payment has been verified.</p></div>
          {application.submitted_at ? <>
            <div className="admission-readonly-status success submission-status"><CheckCircle2 size={18}/><div><strong>Application Submitted</strong><span>Submitted {new Date(application.submitted_at).toLocaleString()}</span></div></div>
            <button type="button" className="secondary-button review-next-action" onClick={() => setActiveTab?.("review")}><ClipboardCheck size={17}/>{application.reviewed_at ? "View / Update Review" : "Start Review"}</button>
          </> : <button type="button" className="primary-action" disabled={!!busy || (fee > 0 && !verifiedPayment)} onClick={() => handleSubmitApplication(application.id)}><Send size={17}/> Submit Application</button>}
        </section>
      </>}
    </div>
  );
}

function CycleForm({ form, setForm, years }) {
  const set = (key) => (e) => setForm({ ...form, [key]: e.target.value });
  const check = (key) => (e) => setForm({ ...form, [key]: e.target.checked });

  return (
    <>
      <label>Academic year<select required value={form.academic_year_id} onChange={set("academic_year_id")}><option value="">Select academic year…</option>{years.map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
      <div className="form-grid">
        <label>Cycle name<input required value={form.name} onChange={set("name")} placeholder="2026/2027 Undergraduate Admissions" /></label>
        <label>Application prefix<input required maxLength="12" value={form.application_prefix} onChange={set("application_prefix")} placeholder="APP" /></label>
      </div>
      <div className="form-grid">
        <label>Admission level<select value={form.admission_level} onChange={set("admission_level")}><option value="undergraduate">Undergraduate</option><option value="postgraduate">Postgraduate</option><option value="both">Both</option></select></label>
        <label>Applicant scope<select value={form.applicant_scope} onChange={set("applicant_scope")}><option value="local">Local only</option><option value="international">International only</option><option value="both">Local & International</option></select></label>
      </div>
      <div className="form-grid">
        <label>Maximum programme choices<input type="number" min="1" max="10" value={form.max_programme_choices} onChange={set("max_programme_choices")} /></label>
        <label>Legacy/default currency<select value={form.currency} onChange={set("currency")}><option value="GHS">GHS</option><option value="USD">USD</option><option value="GBP">GBP</option><option value="EUR">EUR</option></select></label>
      </div>
      <div className="form-grid">
        <label>Opens at<input type="datetime-local" value={form.opens_at} onChange={set("opens_at")} /></label>
        <label>Closes at<input type="datetime-local" value={form.closes_at} onChange={set("closes_at")} /></label>
      </div>
      <div className="form-grid">
        <label>Legacy/default application fee<input type="number" min="0" step="0.01" value={form.application_fee} onChange={set("application_fee")} /></label>
        <label>Instructions<textarea rows="3" value={form.application_instructions} onChange={set("application_instructions")} placeholder="Instructions shown for this intake…" /></label>
      </div>
      <label><input type="checkbox" checked={Boolean(form.payment_required)} onChange={check("payment_required")} /> Application fee/payment is required before submission</label>
      <label><input type="checkbox" checked={Boolean(form.allow_draft_before_payment)} onChange={check("allow_draft_before_payment")} /> Allow applicants to complete a draft before payment</label>
      <div className="form-note">Use <strong>Fees & Requirements</strong> to configure the real Local/International and Undergraduate/Postgraduate fee rules. The legacy fee remains temporarily for compatibility with the existing Paystack Edge Function.</div>
    </>
  );
}

function FeeRuleForm({ form, setForm, data }) {
  const set = (key) => (e) => setForm({ ...form, [key]: e.target.value });
  return <>
    <label>Admission cycle<select required value={form.admission_cycle_id} onChange={set("admission_cycle_id")}><option value="">Select cycle…</option>{data.cycles.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
    <div className="form-grid">
      <label>Applicant category<select value={form.applicant_category} onChange={set("applicant_category")}><option value="local">Local</option><option value="international">International</option></select></label>
      <label>Admission level<select value={form.admission_level} onChange={set("admission_level")}><option value="undergraduate">Undergraduate</option><option value="postgraduate">Postgraduate</option></select></label>
    </div>
    <label>Programme override (optional)<select value={form.programme_id} onChange={set("programme_id")}><option value="">All programmes</option>{data.programmes.map(x=><option key={x.id} value={x.id}>{x.code} — {x.name}</option>)}</select></label>
    <div className="form-grid">
      <label>Amount<input required type="number" min="0" step="0.01" value={form.amount} onChange={set("amount")} /></label>
      <label>Currency<select value={form.currency_code} onChange={set("currency_code")}><option>GHS</option><option>USD</option><option>GBP</option><option>EUR</option></select></label>
    </div>
  </>;
}

function RequirementForm({ form, setForm, data }) {
  const set = (key) => (e) => setForm({ ...form, [key]: e.target.value });
  const check = (key) => (e) => setForm({ ...form, [key]: e.target.checked });
  return <>
    <label>Admission cycle<select required value={form.admission_cycle_id} onChange={set("admission_cycle_id")}><option value="">Select cycle…</option>{data.cycles.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
    <div className="form-grid">
      <label>Applicant category<select value={form.applicant_category} onChange={set("applicant_category")}><option value="both">Both</option><option value="local">Local</option><option value="international">International</option></select></label>
      <label>Admission level<select value={form.admission_level} onChange={set("admission_level")}><option value="both">Both</option><option value="undergraduate">Undergraduate</option><option value="postgraduate">Postgraduate</option></select></label>
    </div>
    <label>Programme override (optional)<select value={form.programme_id} onChange={set("programme_id")}><option value="">All programmes</option>{data.programmes.map(x=><option key={x.id} value={x.id}>{x.code} — {x.name}</option>)}</select></label>
    <div className="form-grid">
      <label>Document code<input required value={form.document_type} onChange={set("document_type")} placeholder="wassce_certificate" /></label>
      <label>Display name<input required value={form.display_name} onChange={set("display_name")} placeholder="WASSCE Certificate" /></label>
    </div>
    <label>Description<textarea rows="2" value={form.description} onChange={set("description")} /></label>
    <label><input type="checkbox" checked={Boolean(form.is_required)} onChange={check("is_required")} /> Required before submission</label>
    <label><input type="checkbox" checked={Boolean(form.requires_verification)} onChange={check("requires_verification")} /> Admissions staff must verify document</label>
  </>;
}

function ApplicantForm({ form, setForm }) {
  const set = (key) => (e) => setForm({ ...form, [key]: e.target.value });

  return (
    <>
      <div className="form-grid">
        <label>First name<input required value={form.first_name} onChange={set("first_name")} /></label>
        <label>Middle name<input value={form.middle_name} onChange={set("middle_name")} /></label>
      </div>
      <div className="form-grid">
        <label>Last name<input required value={form.last_name} onChange={set("last_name")} /></label>
        <label>Date of birth<input type="date" value={form.date_of_birth} onChange={set("date_of_birth")} /></label>
      </div>
      <div className="form-grid">
        <label>Gender<select value={form.gender} onChange={set("gender")}><option value="">Not specified</option><option value="male">Male</option><option value="female">Female</option><option value="other">Other</option></select></label>
        <label>Nationality<input value={form.nationality} onChange={set("nationality")} /></label>
      </div>
      <div className="form-grid">
        <label>Email<input type="email" value={form.email} onChange={set("email")} /></label>
        <label>Phone<input value={form.phone} onChange={set("phone")} /></label>
      </div>
      <div className="form-grid">
        <label>Country of residence<input value={form.country_of_residence} onChange={set("country_of_residence")} /></label>
        <label>Region<input value={form.region} onChange={set("region")} /></label>
      </div>
      <div className="form-grid">
        <label>City<input value={form.city} onChange={set("city")} /></label>
        <label>Address<input value={form.address} onChange={set("address")} /></label>
      </div>
      <div className="form-grid">
        <label>Emergency contact<input value={form.emergency_contact_name} onChange={set("emergency_contact_name")} /></label>
        <label>Emergency phone<input value={form.emergency_contact_phone} onChange={set("emergency_contact_phone")} /></label>
      </div>
    </>
  );
}

function ApplicationForm({ form, setForm, data }) {
  const set = (key) => (e) => setForm({ ...form, [key]: e.target.value });

  return (
    <>
      <label>Admission cycle<select required value={form.admission_cycle_id} onChange={set("admission_cycle_id")}><option value="">Select cycle…</option>{data.cycles.map((row) => <option key={row.id} value={row.id}>{row.name} ({row.status})</option>)}</select></label>
      <label>Applicant<select required value={form.applicant_id} onChange={set("applicant_id")}><option value="">Select applicant…</option>{data.applicants.map((row) => <option key={row.id} value={row.id}>{applicantName(row)}{row.email ? ` — ${row.email}` : ""}</option>)}</select></label>
      <label>Entry type<select value={form.entry_type} onChange={set("entry_type")}><option value="regular">Regular</option><option value="mature">Mature</option><option value="transfer">Transfer</option><option value="international">International</option></select></label>
      <label>First programme choice<select required value={form.first_programme_id} onChange={set("first_programme_id")}><option value="">Select programme…</option>{data.programmes.map((row) => <option key={row.id} value={row.id}>{row.code} — {row.name}</option>)}</select></label>
      <label>Second programme choice<select value={form.second_programme_id} onChange={set("second_programme_id")}><option value="">No second choice</option>{data.programmes.map((row) => <option key={row.id} value={row.id}>{row.code} — {row.name}</option>)}</select></label>
      <label>Internal notes<textarea rows="3" value={form.notes} onChange={set("notes")} /></label>
      <div className="form-note">This Phase 1 internal workflow creates a <strong>draft</strong> application. Submission, review, document verification, offers and student conversion follow in Phase 2.</div>
    </>
  );
}
