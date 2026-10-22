import {useConfirm} from "../../contexts/ConfirmContext";
import Toast from "../../components/Toast";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  BookOpen,
  Building2,
  CalendarClock,
  CalendarRange,
  CheckCircle2,
  CircleOff,
  Clock3,
  GraduationCap,
  Layers3,
  LibraryBig,
  Network,
  Pencil,
  Plus,
  RefreshCw,
  Search,
  School,
  UserRoundCheck,
  Trash2,
  X,
} from "lucide-react";
import { useUserContext } from "../../contexts/UserContext";
import DashboardSectionMenu from "../../components/navigation/DashboardSectionMenu";
import {
  loadAcademicSetup,
  saveAcademicRecord,
  setAcademicRecordStatus,
  setCurrentAcademicPeriod,
  setCurrentAcademicYear,
  bulkAssignLecturer,
  removeLecturerAllocation,
} from "../../services/academics";

const TAB_CONFIG = [
  { key: "years", label: "Academic Years", icon: CalendarRange },
  { key: "periods", label: "Semesters", icon: Layers3 },
  { key: "faculties", label: "Faculties", icon: Building2 },
  { key: "schools", label: "Schools", icon: School },
  { key: "departments", label: "Departments", icon: Network },
  { key: "programmes", label: "Programmes", icon: GraduationCap },
  { key: "courses", label: "Courses", icon: BookOpen },
  { key: "curriculum", label: "Curriculum", icon: LibraryBig },
  { key: "offerings", label: "Course Offerings", icon: CalendarClock },
  { key: "lecturers", label: "Lecturer Allocation", icon: UserRoundCheck },
  { key: "schedules", label: "Timetable", icon: Clock3 },
];

const ACADEMICS_MENU_GROUPS = [
  { label: "Calendar", items: TAB_CONFIG.filter(({ key }) => ["years", "periods"].includes(key)) },
  { label: "Academic Structure", items: TAB_CONFIG.filter(({ key }) => ["faculties", "schools", "departments"].includes(key)) },
  { label: "Curriculum", items: TAB_CONFIG.filter(({ key }) => ["programmes", "courses", "curriculum"].includes(key)) },
  { label: "Teaching", items: TAB_CONFIG.filter(({ key }) => ["offerings", "lecturers", "schedules"].includes(key)) },
];

const ENTITY_LABEL = {
  years: "Academic Year",
  periods: "Semester / Period",
  faculties: "Faculty",
  schools: "School",
  departments: "Department",
  programmes: "Programme",
  courses: "Course",
  curriculum: "Curriculum Course",
  offerings: "Course Offering",
  lecturers: "Lecturer Allocation",
  schedules: "Schedule",
};

const EMPTY = {
  years: { name: "", start_date: "", end_date: "", status: "planned" },
  periods: {
    academic_year_id: "", name: "", period_type: "semester", period_number: 1,
    start_date: "", end_date: "", registration_start: "", registration_end: "",
    status: "planned",
  },
  faculties: { name: "", code: "", description: "", status: "active" },
  schools: { faculty_id: "", name: "", code: "", description: "", status: "active" },
  departments: {
    faculty_id: "", school_id: "", name: "", code: "", description: "", status: "active",
  },
  programmes: {
    department_id: "", name: "", code: "", award_type: "", duration_years: "",
    total_credits: "", description: "", status: "active",
  },
  courses: {
    department_id: "", name: "", code: "", course_type: "course", credit_hours: 0,
    lecture_hours: 0, practical_hours: 0, description: "", status: "active",
  },
  curriculum: {
    programme_id: "", course_id: "", level_number: 100, period_number: 1,
    course_category: "core", is_required: true,
  },
  offerings: {
    course_id: "", academic_year_id: "", academic_period_id: "",
    department_id: "", programme_id: "", level_number: 100, section_code: "A",
    capacity: "", delivery_mode: "in_person", status: "planned",
    registration_open: true, notes: "",
  },
  lecturers: {
    course_offering_id: "", lecturer_profile_id: "", allocation_role: "lecturer",
    workload_percentage: 100, is_primary: false,
  },
  schedules: {
    course_offering_id: "", day_of_week: 1, start_time: "", end_time: "",
    venue: "", schedule_type: "lecture",
  },
};

const DAYS = [
  [1, "Monday"], [2, "Tuesday"], [3, "Wednesday"], [4, "Thursday"],
  [5, "Friday"], [6, "Saturday"], [7, "Sunday"],
];

function clean(entity, form) {
  const payload = { ...form };
  Object.keys(payload).forEach((key) => {
    if (payload[key] === "") payload[key] = null;
  });

  const numeric = {
    periods: ["period_number"],
    programmes: ["duration_years", "total_credits"],
    courses: ["credit_hours", "lecture_hours", "practical_hours"],
    curriculum: ["level_number", "period_number"],
    offerings: ["level_number", "capacity"],
    lecturers: ["workload_percentage"],
    schedules: ["day_of_week"],
  }[entity] || [];

  numeric.forEach((key) => {
    if (payload[key] !== null) payload[key] = Number(payload[key]);
  });

  return payload;
}

function staffName(profile) {
  const staff = profile?.staff;
  if (!staff) return "Unnamed lecturer";

  const name = [staff.first_name, staff.middle_name, staff.last_name]
    .filter(Boolean)
    .join(" ");

  return `${name || staff.email || "Unnamed lecturer"}${profile.academic_rank ? ` — ${profile.academic_rank}` : ""}`;
}

function offeringLabel(offering) {
  if (!offering) return "Unknown offering";
  const course = offering.course;
  const period = offering.academic_period;
  return `${course?.code || "Course"} — ${course?.name || ""} / ${period?.name || ""} / Sec ${offering.section_code || "A"}`;
}

function isProgrammeActive(row) {
  const status = String(row?.status || "").trim().toLowerCase();
  // Existing UniMIS data may use active, published, open, or blank for usable programmes.
  // Only explicitly retired states are excluded from operational selectors.
  return !["inactive","deactivated","archived","closed","cancelled"].includes(status);
}


export default function AcademicsManagement() {
  const confirmAction=useConfirm();
  const { institutionId } = useUserContext();

  const [activeTab, setActiveTab] = useState("years");
  const [data, setData] = useState({
    years: [], periods: [], faculties: [], schools: [], departments: [],
    programmes: [], courses: [], curriculum: [], offerings: [], lecturers: [],
    schedules: [], lecturerProfiles: [],
  });
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [modal, setModal] = useState(null);
  const [form, setForm] = useState({ ...EMPTY.years });

  const [bulkLecturer, setBulkLecturer] = useState({
    academic_year_id: "",
    academic_period_id: "",
    lecturer_profile_id: "",
    programme_id: "",
    department_id: "",
    level_number: "",
    allocation_role: "lecturer",
    workload_percentage: 100,
    is_primary: false,
  });
  const [selectedOfferings, setSelectedOfferings] = useState([]);
  const [curriculumSelectedCourseIds, setCurriculumSelectedCourseIds] = useState([]);
  const [showInactiveProgrammes, setShowInactiveProgrammes] = useState(false);
  const [offeringGeneratorOpen, setOfferingGeneratorOpen] = useState(false);
  const [offeringGenerator, setOfferingGenerator] = useState({
    programme_id: "",
    academic_year_id: "",
    academic_period_id: "",
    level_number: 100,
    section_code: "A",
    delivery_mode: "in_person",
    selected_course_ids: [],
  });

  const load = useCallback(async () => {
    if (!institutionId) {
      setLoading(false);
      return;
    }

    setLoading(true);
    setError("");

    const result = await loadAcademicSetup(institutionId);
    if (result.error) setError(result.error.message);
    else setData(result.data);

    setLoading(false);
  }, [institutionId]);

  useEffect(() => {
    load();
  }, [load]);

  const currentYear = data.years.find((row) => row.is_current);
  const currentPeriod = data.periods.find((row) => row.is_current);
  const activeProgrammes = useMemo(
    () => (data.programmes || []).filter(isProgrammeActive),
    [data.programmes]
  );

  useEffect(() => {
    if (!bulkLecturer.academic_year_id && currentYear?.id) {
      setBulkLecturer((prev) => ({
        ...prev,
        academic_year_id: currentYear.id,
        academic_period_id:
          currentPeriod?.academic_year_id === currentYear.id
            ? currentPeriod.id
            : "",
      }));
    }
  }, [
    currentYear?.id,
    currentPeriod?.id,
    currentPeriod?.academic_year_id,
    bulkLecturer.academic_year_id,
  ]);

  const rows = useMemo(() => {
    const search = query.trim().toLowerCase();
    if (!search) return data[activeTab] || [];

    return (data[activeTab] || []).filter((row) => {
      if (activeTab === "programmes" && !showInactiveProgrammes && !isProgrammeActive(row)) return false;
      if (activeTab === "curriculum" && row.programme && !isProgrammeActive(row.programme)) return false;
      const lecturer = row.lecturer_profile ? staffName(row.lecturer_profile) : "";
      const offering = row.course_offering ? offeringLabel(row.course_offering) : "";

      return [
        row.name, row.code, row.description, row.status, row.award_type,
        row.department?.name, row.faculty?.name, row.school?.name,
        row.academic_year?.name, row.academic_period?.name,
        row.programme?.name, row.course?.name, row.course?.code,
        lecturer, offering, row.venue, row.schedule_type, row.allocation_role,
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase()
        .includes(search);
    });
  }, [activeTab, data, query, showInactiveProgrammes]);

  function openCreate() {
    const next = { ...EMPTY[activeTab] };

    if (activeTab === "curriculum") {
      setCurriculumSelectedCourseIds([]);
    }

    if (activeTab === "offerings") {
      if (currentYear) next.academic_year_id = currentYear.id;
      if (currentPeriod) next.academic_period_id = currentPeriod.id;
    }

    setForm(next);
    setModal({ entity: activeTab, id: null, mode: "create" });
    setError("");
    setMessage("");
  }

  function openEdit(row) {
    const next = {};
    Object.keys(EMPTY[activeTab]).forEach((key) => {
      next[key] = row[key] ?? EMPTY[activeTab][key];
    });

    setForm(next);
    setModal({ entity: activeTab, id: row.id, mode: "edit" });
    setError("");
    setMessage("");
  }

  async function submit(e) {
    e.preventDefault();
    if (!modal || !institutionId) return;

    setBusy("save");
    setError("");
    setMessage("");

    const payload = clean(modal.entity, form);

    if (modal.entity === "curriculum" && modal.mode === "create") {
      if (!payload.programme_id) {
        setError("Select an active programme.");
        setBusy("");
        return;
      }
      if (!curriculumSelectedCourseIds.length) {
        setError("Select at least one course.");
        setBusy("");
        return;
      }

      const existingCourseIds = new Set(
        (data.curriculum || [])
          .filter((row) =>
            row.programme_id === payload.programme_id &&
            Number(row.level_number) === Number(payload.level_number) &&
            Number(row.period_number) === Number(payload.period_number)
          )
          .map((row) => row.course_id)
      );

      const toCreate = curriculumSelectedCourseIds.filter((id) => !existingCourseIds.has(id));
      if (!toCreate.length) {
        setError("All selected courses are already in this programme curriculum for the selected level and semester.");
        setBusy("");
        return;
      }

      for (const courseId of toCreate) {
        const result = await saveAcademicRecord(
          "curriculum",
          institutionId,
          {
            programme_id: payload.programme_id,
            course_id: courseId,
            level_number: payload.level_number,
            period_number: payload.period_number,
            course_category: payload.course_category,
            is_required: payload.is_required,
          },
          null
        );
        if (result.error) {
          setError(result.error.message);
          setBusy("");
          return;
        }
      }

      setMessage(`${toCreate.length} curriculum course${toCreate.length===1?"":"s"} added successfully.`);
      setModal(null);
      setCurriculumSelectedCourseIds([]);
      await load();
      setBusy("");
      return;
    }

    if (modal.entity === "departments" && payload.school_id) {
      const school = data.schools.find((row) => row.id === payload.school_id);
      if (school?.faculty_id) payload.faculty_id = school.faculty_id;
    }

    if (modal.entity === "offerings") {
      const period = data.periods.find((row) => row.id === payload.academic_period_id);
      if (period && period.academic_year_id !== payload.academic_year_id) {
        setError("The selected semester does not belong to the selected academic year.");
        setBusy("");
        return;
      }
    }

    if (modal.entity === "schedules" && payload.start_time && payload.end_time) {
      if (payload.end_time <= payload.start_time) {
        setError("End time must be later than start time.");
        setBusy("");
        return;
      }
    }

    const result = await saveAcademicRecord(
      modal.entity,
      institutionId,
      payload,
      modal.id
    );

    if (result.error) {
      setError(result.error.message);
    } else {
      setMessage(
        `${ENTITY_LABEL[modal.entity]} ${modal.mode === "edit" ? "updated" : "created"} successfully.`
      );
      setModal(null);
      await load();
    }

    setBusy("");
  }

  async function toggleStatus(entity, row) {
    const next =
      entity === "offerings"
        ? row.status === "open"
          ? "closed"
          : "open"
        : row.status === "active"
          ? "inactive"
          : "active";

    setBusy(row.id);
    setError("");
    setMessage("");

    const result = await setAcademicRecordStatus(entity, row.id, next);

    if (result.error) {
      setError(result.error.message);
    } else {
      const label =
        entity === "offerings"
          ? next === "open"
            ? "opened"
            : "closed"
          : next === "active"
            ? "activated"
            : "deactivated";

      setMessage(`${ENTITY_LABEL[entity]} ${label}.`);
      await load();
    }

    setBusy("");
  }

  async function makeCurrentYear(row) {
    setBusy(row.id);
    setError("");
    const result = await setCurrentAcademicYear(institutionId, row.id);
    if (result.error) setError(result.error.message);
    else {
      setMessage(`${row.name} is now the current academic year.`);
      await load();
    }
    setBusy("");
  }

  async function makeCurrentPeriod(row) {
    setBusy(row.id);
    setError("");
    const result = await setCurrentAcademicPeriod(institutionId, row.academic_year_id, row.id);
    if (result.error) setError(result.error.message);
    else {
      setMessage(`${row.name} is now the current academic period.`);
      await load();
    }
    setBusy("");
  }

  function openOfferingGenerator() {
    const year = currentYear || data.years.find((row) => row.status === "active") || data.years[0];
    const period =
      currentPeriod ||
      data.periods.find((row) => row.academic_year_id === year?.id && row.status === "active") ||
      data.periods.find((row) => row.academic_year_id === year?.id);

    setOfferingGenerator({
      programme_id: "",
      academic_year_id: year?.id || "",
      academic_period_id: period?.id || "",
      level_number: 100,
      section_code: "A",
      delivery_mode: "in_person",
      selected_course_ids: [],
    });
    setOfferingGeneratorOpen(true);
    setError("");
  }

  async function generateOfferings() {
    const g = offeringGenerator;
    if (!g.programme_id || !g.academic_year_id || !g.academic_period_id) {
      setError("Programme, academic year and semester are required.");
      return;
    }
    if (!g.selected_course_ids.length) {
      setError("Select at least one curriculum course.");
      return;
    }

    const programme = data.programmes.find((row) => row.id === g.programme_id);
    const departmentId = programme?.department_id || null;
    const existing = new Set(
      data.offerings
        .filter((row) =>
          row.academic_year_id === g.academic_year_id &&
          row.academic_period_id === g.academic_period_id &&
          Number(row.level_number) === Number(g.level_number) &&
          (row.programme_id === g.programme_id || row.programme_id == null) &&
          String(row.section_code || "A") === String(g.section_code || "A")
        )
        .map((row) => row.course_id)
    );

    const courseIds = g.selected_course_ids.filter((id) => !existing.has(id));
    if (!courseIds.length) {
      setError("All selected curriculum courses already have course offerings for this semester.");
      return;
    }

    setBusy("generate-offerings");
    setError("");
    setMessage("");

    for (const courseId of courseIds) {
      const result = await saveAcademicRecord(
        "offerings",
        institutionId,
        {
          course_id: courseId,
          academic_year_id: g.academic_year_id,
          academic_period_id: g.academic_period_id,
          department_id: departmentId,
          programme_id: g.programme_id,
          level_number: Number(g.level_number),
          section_code: g.section_code || "A",
          capacity: null,
          delivery_mode: g.delivery_mode || "in_person",
          status: "open",
          registration_open: true,
          notes: "Generated from programme curriculum",
        },
        null
      );
      if (result.error) {
        const duplicate = String(result.error.message||"").toLowerCase().includes("duplicate key");
        setError(duplicate
          ? "A matching course offering already exists for this course/semester/programme/section. Refresh Course Offerings and generate only the remaining courses."
          : result.error.message);
        setBusy("");
        return;
      }
    }

    setMessage(`${courseIds.length} course offering${courseIds.length===1?"":"s"} created and opened for registration.`);
    setOfferingGeneratorOpen(false);
    setBusy("");
    await load();
  }

  const bulkPeriods = bulkLecturer.academic_year_id
    ? data.periods.filter(
        (row) => row.academic_year_id === bulkLecturer.academic_year_id
      )
    : data.periods;

  const bulkOfferingRows = data.offerings.filter((row) => {
    if (
      bulkLecturer.academic_year_id &&
      row.academic_year_id !== bulkLecturer.academic_year_id
    ) return false;

    if (
      bulkLecturer.academic_period_id &&
      row.academic_period_id !== bulkLecturer.academic_period_id
    ) return false;

    if (
      bulkLecturer.programme_id &&
      row.programme_id !== bulkLecturer.programme_id
    ) return false;

    if (
      bulkLecturer.department_id &&
      row.department_id !== bulkLecturer.department_id
    ) return false;

    if (
      bulkLecturer.level_number &&
      String(row.level_number || "") !== String(bulkLecturer.level_number)
    ) return false;

    return true;
  });

  const selectedLecturerExisting = new Set(
    data.lecturers
      .filter(
        (row) =>
          row.lecturer_profile_id === bulkLecturer.lecturer_profile_id
      )
      .map((row) => row.course_offering_id)
  );

  const allSelectableOfferingIds = bulkOfferingRows
    .filter((row) => !selectedLecturerExisting.has(row.id))
    .map((row) => row.id);

  function toggleOffering(id) {
    setSelectedOfferings((current) =>
      current.includes(id)
        ? current.filter((value) => value !== id)
        : [...current, id]
    );
  }

  function selectAllOfferings() {
    setSelectedOfferings(allSelectableOfferingIds);
  }

  function clearSelectedOfferings() {
    setSelectedOfferings([]);
  }

  async function assignSelectedOfferings() {
    if (!bulkLecturer.lecturer_profile_id) {
      setError("Select a lecturer.");
      return;
    }

    if (!selectedOfferings.length) {
      setError("Select at least one course offering.");
      return;
    }

    setBusy("bulk-lecturer");
    setError("");
    setMessage("");

    const result = await bulkAssignLecturer({
      institutionId,
      lecturerProfileId: bulkLecturer.lecturer_profile_id,
      courseOfferingIds: selectedOfferings,
      allocationRole: bulkLecturer.allocation_role,
      workloadPercentage: bulkLecturer.workload_percentage,
      makePrimary: bulkLecturer.is_primary,
    });

    if (result.error) {
      setError(result.error.message);
    } else {
      const inserted = result.data?.inserted || 0;
      const skipped = result.data?.skipped || 0;
      setMessage(
        `${inserted} course allocation${inserted === 1 ? "" : "s"} created` +
        (skipped ? `; ${skipped} existing allocation${skipped === 1 ? "" : "s"} skipped.` : ".")
      );
      setSelectedOfferings([]);
      await load();
    }

    setBusy("");
  }

  async function removeAllocation(row) {
    const okay = await confirmAction({
      title:"Remove lecturer allocation?",
      message:`Remove ${staffName(row.lecturer_profile)} from ${offeringLabel(row.course_offering)}?`,
      confirmLabel:"Remove allocation",
      tone:"danger"
    });
    if (!okay) return;

    setBusy(row.id);
    setError("");
    setMessage("");

    const result = await removeLecturerAllocation(row.id);

    if (result.error) {
      setError(result.error.message);
    } else {
      setMessage("Lecturer allocation removed.");
      await load();
    }

    setBusy("");
  }

  return (
    <section>
      <div className="page-heading academics-heading">
        <div>
          <span className="eyebrow">Administration</span>
          <h1>Academic Management</h1>
          <p>
            Configure academic structure, curriculum, course offerings, lecturer
            allocation and timetable before Admissions and teaching operations.
          </p>
        </div>

        <button type="button" className="secondary-button" onClick={load}>
          <RefreshCw size={17} />
          Refresh
        </button>
      </div>

      <Toast message={error||message} type={error?"error":"success"} onClose={()=>{setError("");setMessage("")}}/>

      <div className="academic-summary-grid">
        <div><CalendarRange /><span>Current Academic Year</span><strong>{currentYear?.name || "Not set"}</strong></div>
        <div><Layers3 /><span>Current Semester</span><strong>{currentPeriod?.name || "Not set"}</strong></div>
        <div><GraduationCap /><span>Programmes</span><strong>{data.programmes.length}</strong></div>
        <div><BookOpen /><span>Course Offerings</span><strong>{data.offerings.length}</strong></div>
      </div>

      <div className="management-card academics-card">
        <DashboardSectionMenu
          groups={ACADEMICS_MENU_GROUPS}
          activeKey={activeTab}
          onSelect={(key) => {
            setActiveTab(key);
            setQuery("");
          }}
          className="academics-section-menu"
        />

        {activeTab === "lecturers" ? (
          <BulkLecturerAllocation
            data={data}
            bulk={bulkLecturer}
            setBulk={setBulkLecturer}
            periods={bulkPeriods}
            offeringRows={bulkOfferingRows}
            existingOfferingIds={selectedLecturerExisting}
            selectedOfferings={selectedOfferings}
            toggleOffering={toggleOffering}
            selectAllOfferings={selectAllOfferings}
            clearSelectedOfferings={clearSelectedOfferings}
            assignSelectedOfferings={assignSelectedOfferings}
            busy={busy}
            allocations={rows}
            query={query}
            setQuery={setQuery}
            removeAllocation={removeAllocation}
          />
        ) : (
          <>
            <div className="academics-toolbar">
              <label className="search-box">
                <Search size={17} />
                <input
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder={`Search ${ENTITY_LABEL[activeTab].toLowerCase()}…`}
                />
              </label>

              {activeTab === "programmes" && (
                <label className="checkbox-row academics-show-inactive">
                  <input
                    type="checkbox"
                    checked={showInactiveProgrammes}
                    onChange={(e) => setShowInactiveProgrammes(e.target.checked)}
                  />
                  Show inactive programmes
                </label>
              )}

              {activeTab === "offerings" && (
                <button type="button" className="secondary-button" onClick={openOfferingGenerator}>
                  <LibraryBig size={17} />
                  Generate from Curriculum
                </button>
              )}

              <button type="button" className="primary-action" onClick={openCreate}>
                <Plus size={18} />
                {activeTab === "curriculum" ? "Assign Courses" : `Add ${ENTITY_LABEL[activeTab]}`}
              </button>
            </div>

            {loading ? (
              <div className="table-empty">Loading academic setup…</div>
            ) : (
              <AcademicTable
                entity={activeTab}
                rows={rows}
                busy={busy}
                onEdit={openEdit}
                onToggle={toggleStatus}
                onCurrentYear={makeCurrentYear}
                onCurrentPeriod={makeCurrentPeriod}
              />
            )}
          </>
        )}
      </div>

      {offeringGeneratorOpen && (
        <OfferingGeneratorModal
          data={data}
          activeProgrammes={activeProgrammes}
          form={offeringGenerator}
          setForm={setOfferingGenerator}
          onClose={() => setOfferingGeneratorOpen(false)}
          onGenerate={generateOfferings}
          busy={busy === "generate-offerings"}
        />
      )}

      {modal && (
        <div
          className="modal-backdrop"
          onMouseDown={(e) => {
            if (e.target === e.currentTarget) setModal(null);
          }}
        >
          <div className="modal-card academic-modal">
            <div className="section-title">
              <div>
                <h2>{modal.mode === "edit" ? "Edit" : "Add"} {ENTITY_LABEL[modal.entity]}</h2>
                <p>Complete the academic operation information below.</p>
              </div>

              <button type="button" className="icon-button" onClick={() => setModal(null)} aria-label="Close">
                <X size={19} />
              </button>
            </div>

            <form className="user-form" onSubmit={submit}>
              <AcademicForm
                entity={modal.entity}
                form={form}
                setForm={setForm}
                data={data}
                activeProgrammes={activeProgrammes}
                curriculumSelectedCourseIds={curriculumSelectedCourseIds}
                setCurriculumSelectedCourseIds={setCurriculumSelectedCourseIds}
                mode={modal.mode}
              />

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

function BulkLecturerAllocation({
  data,
  bulk,
  setBulk,
  periods,
  offeringRows,
  existingOfferingIds,
  selectedOfferings,
  toggleOffering,
  selectAllOfferings,
  clearSelectedOfferings,
  assignSelectedOfferings,
  busy,
  allocations,
  query,
  setQuery,
  removeAllocation,
}) {
  const set = (key) => (e) => {
    const value =
      e.target.type === "checkbox" ? e.target.checked : e.target.value;

    setBulk((prev) => {
      const next = { ...prev, [key]: value };

      if (key === "academic_year_id") {
        next.academic_period_id = "";
      }

      return next;
    });
  };

  return (
    <div className="bulk-lecturer-workspace">
      <div className="bulk-allocation-panel">
        <div className="section-title">
          <div>
            <h2>Bulk Semester Lecturer Allocation</h2>
            <p>
              Select a lecturer, filter semester course offerings, then assign
              several courses in one operation.
            </p>
          </div>
        </div>

        <div className="bulk-filter-grid">
          <label>
            Academic year
            <select
              value={bulk.academic_year_id}
              onChange={set("academic_year_id")}
            >
              <option value="">All years</option>
              {data.years.map((row) => (
                <option key={row.id} value={row.id}>
                  {row.name}
                </option>
              ))}
            </select>
          </label>

          <label>
            Semester
            <select
              value={bulk.academic_period_id}
              onChange={set("academic_period_id")}
            >
              <option value="">All semesters</option>
              {periods.map((row) => (
                <option key={row.id} value={row.id}>
                  {row.name}
                </option>
              ))}
            </select>
          </label>

          <label>
            Lecturer
            <select
              required
              value={bulk.lecturer_profile_id}
              onChange={set("lecturer_profile_id")}
            >
              <option value="">Select lecturer…</option>
              {data.lecturerProfiles.map((row) => (
                <option key={row.id} value={row.id}>
                  {staffName(row)}
                </option>
              ))}
            </select>
          </label>

          <label>
            Programme
            <select value={bulk.programme_id} onChange={set("programme_id")}>
              <option value="">All programmes</option>
              {data.programmes.filter(isProgrammeActive).map((row) => (
                <option key={row.id} value={row.id}>
                  {row.code} — {row.name}
                </option>
              ))}
            </select>
          </label>

          <label>
            Department
            <select value={bulk.department_id} onChange={set("department_id")}>
              <option value="">All departments</option>
              {data.departments.map((row) => (
                <option key={row.id} value={row.id}>
                  {row.name}
                </option>
              ))}
            </select>
          </label>

          <label>
            Level
            <select value={bulk.level_number} onChange={set("level_number")}>
              <option value="">All levels</option>
              {[100, 200, 300, 400, 500, 600, 700].map((level) => (
                <option key={level} value={level}>
                  {level}
                </option>
              ))}
            </select>
          </label>
        </div>

        <div className="bulk-role-row">
          <label>
            Allocation role
            <select value={bulk.allocation_role} onChange={set("allocation_role")}>
              <option value="lecturer">Lecturer</option>
              <option value="co_lecturer">Co-lecturer</option>
              <option value="tutor">Tutor</option>
              <option value="supervisor">Supervisor</option>
            </select>
          </label>

          <label>
            Workload %
            <input
              type="number"
              min="0"
              max="100"
              value={bulk.workload_percentage}
              onChange={set("workload_percentage")}
            />
          </label>

          <label className="checkbox-row bulk-primary-check">
            <input
              type="checkbox"
              checked={Boolean(bulk.is_primary)}
              onChange={set("is_primary")}
            />
            Make primary lecturer
          </label>
        </div>

        <div className="bulk-selection-header">
          <div>
            <strong>{selectedOfferings.length}</strong> course
            {selectedOfferings.length === 1 ? "" : "s"} selected
          </div>

          <div className="bulk-selection-actions">
            <button
              type="button"
              className="secondary-button"
              onClick={selectAllOfferings}
            >
              Select all available
            </button>

            <button
              type="button"
              className="secondary-button"
              onClick={clearSelectedOfferings}
            >
              Clear
            </button>
          </div>
        </div>

        <BulkOfferingCards
          offeringRows={offeringRows}
          bulk={bulk}
          existingOfferingIds={existingOfferingIds}
          selectedOfferings={selectedOfferings}
          toggleOffering={toggleOffering}
        />

        <div className="responsive-table bulk-offering-desktop-table">
          <table className="academic-table bulk-offering-table">
            <thead>
              <tr>
                <th>Select</th>
                <th>Course</th>
                <th>Semester</th>
                <th>Programme</th>
                <th>Level</th>
                <th>Section</th>
                <th>Assignment</th>
              </tr>
            </thead>

            <tbody>
              {offeringRows.map((row) => {
                const alreadyAssigned =
                  bulk.lecturer_profile_id &&
                  existingOfferingIds.has(row.id);

                const checked = selectedOfferings.includes(row.id);

                return (
                  <tr
                    key={row.id}
                    className={alreadyAssigned ? "allocation-existing-row" : ""}
                  >
                    <td>
                      <input
                        type="checkbox"
                        checked={checked}
                        disabled={!bulk.lecturer_profile_id || alreadyAssigned}
                        onChange={() => toggleOffering(row.id)}
                      />
                    </td>

                    <td>
                      <strong>{row.course?.code || "—"}</strong>
                      <div className="cell-note">
                        {row.course?.name || ""}
                      </div>
                    </td>

                    <td>
                      {row.academic_period?.name || "—"}
                      <div className="cell-note">
                        {row.academic_year?.name || ""}
                      </div>
                    </td>

                    <td>{row.programme?.name || "Institution-wide"}</td>
                    <td>{row.level_number || "—"}</td>
                    <td>{row.section_code || "A"}</td>

                    <td>
                      {alreadyAssigned ? (
                        <span className="status-pill active">Already assigned</span>
                      ) : (
                        <span className="status-pill planned">Available</span>
                      )}
                    </td>
                  </tr>
                );
              })}

              {!offeringRows.length && (
                <tr>
                  <td colSpan="7" className="table-empty">
                    No course offerings match the selected filters.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        <div className="bulk-assign-footer">
          <button
            type="button"
            className="primary-action"
            disabled={
              busy === "bulk-lecturer" ||
              !bulk.lecturer_profile_id ||
              !selectedOfferings.length
            }
            onClick={assignSelectedOfferings}
          >
            <UserRoundCheck size={18} />
            {busy === "bulk-lecturer"
              ? "Assigning…"
              : `Assign ${selectedOfferings.length || ""} Selected Course${
                  selectedOfferings.length === 1 ? "" : "s"
                }`}
          </button>
        </div>
      </div>

      <div className="bulk-existing-panel">
        <div className="section-title">
          <div>
            <h2>Existing Lecturer Allocations</h2>
            <p>
              Review current allocations and remove individual records when needed.
            </p>
          </div>
        </div>

        <div className="academics-toolbar">
          <label className="search-box">
            <Search size={17} />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search lecturer allocation…"
            />
          </label>
        </div>

        <div className="responsive-table">
          <table className="academic-table">
            <thead>
              <tr>
                <th>Course Offering</th>
                <th>Lecturer</th>
                <th>Role</th>
                <th>Workload</th>
                <th>Primary</th>
                <th>Actions</th>
              </tr>
            </thead>

            <tbody>
              {allocations.map((row) => (
                <tr key={row.id}>
                  <td>{offeringLabel(row.course_offering)}</td>
                  <td>
                    <strong>{staffName(row.lecturer_profile)}</strong>
                    <div className="cell-note">
                      {row.lecturer_profile?.specialization || ""}
                    </div>
                  </td>
                  <td>{row.allocation_role}</td>
                  <td>{row.workload_percentage}%</td>
                  <td>
                    {row.is_primary ? (
                      <span className="status-pill active">Primary</span>
                    ) : (
                      "—"
                    )}
                  </td>
                  <td>
                    <button
                      type="button"
                      className="table-action danger"
                      disabled={!!busy}
                      onClick={() => removeAllocation(row)}
                    >
                      <Trash2 size={14} />
                      Remove
                    </button>
                  </td>
                </tr>
              ))}

              {!allocations.length && (
                <tr>
                  <td colSpan="6" className="table-empty">
                    No lecturer allocations yet.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

function BulkOfferingCards({
  offeringRows,
  bulk,
  existingOfferingIds,
  selectedOfferings,
  toggleOffering,
}) {
  return (
    <div className="bulk-offering-cards">
      {offeringRows.map((row) => {
        const alreadyAssigned =
          bulk.lecturer_profile_id && existingOfferingIds.has(row.id);
        const checked = selectedOfferings.includes(row.id);

        return (
          <label
            key={row.id}
            className={alreadyAssigned ? "bulk-offering-card is-disabled" : "bulk-offering-card"}
          >
            <div className="bulk-offering-card-check">
              <input
                type="checkbox"
                checked={checked}
                disabled={!bulk.lecturer_profile_id || alreadyAssigned}
                onChange={() => toggleOffering(row.id)}
              />
            </div>

            <div className="bulk-offering-card-body">
              <div className="bulk-offering-card-title">
                <strong>{row.course?.code || "—"}</strong>
                <span>{row.course?.name || ""}</span>
              </div>
              <div className="bulk-offering-card-meta">
                <span>{row.programme?.name || "Institution-wide"}</span>
                <span>{row.academic_period?.name || "—"}</span>
                <span>Level {row.level_number || "—"}</span>
                <span>Sec {row.section_code || "A"}</span>
              </div>
            </div>

            <div className="bulk-offering-card-status">
              {alreadyAssigned ? (
                <span className="status-pill active">Assigned</span>
              ) : (
                <span className={`status-pill ${row.status}`}>{row.status || "available"}</span>
              )}
            </div>
          </label>
        );
      })}

      {!offeringRows.length && (
        <div className="table-empty">No course offerings match the selected filters.</div>
      )}
    </div>
  );
}

function OfferingGeneratorModal({data,activeProgrammes,form,setForm,onClose,onGenerate,busy}) {
  const periods = form.academic_year_id
    ? data.periods.filter((row)=>row.academic_year_id===form.academic_year_id)
    : data.periods;

  const selectedPeriod = data.periods.find((row)=>row.id===form.academic_period_id);
  const periodNumber = selectedPeriod?.period_number;

  const curriculumRows = (data.curriculum || []).filter((row)=>
    row.programme_id===form.programme_id &&
    Number(row.level_number)===Number(form.level_number) &&
    (!periodNumber || Number(row.period_number)===Number(periodNumber))
  );

  const existingCourseIds = new Set(
    (data.offerings || [])
      .filter((row)=>
        row.academic_year_id===form.academic_year_id &&
        row.academic_period_id===form.academic_period_id &&
        Number(row.level_number)===Number(form.level_number) &&
        (row.programme_id===form.programme_id || row.programme_id==null) &&
        String(row.section_code||"A")===String(form.section_code||"A")
      )
      .map((row)=>row.course_id)
  );

  const availableRows = curriculumRows.filter((row)=>!existingCourseIds.has(row.course_id));
  const availableIds = availableRows.map((row)=>row.course_id);
  const allSelected = availableIds.length>0 && availableIds.every((id)=>form.selected_course_ids.includes(id));
  const set=(key)=>(e)=>{
    const value=e.target.value;
    setForm((prev)=>{
      const next={...prev,[key]:value};
      if(key==="academic_year_id"){next.academic_period_id="";next.selected_course_ids=[];}
      if(["programme_id","academic_period_id","level_number"].includes(key))next.selected_course_ids=[];
      return next;
    });
  };
  const toggle=(id)=>setForm((prev)=>({...prev,selected_course_ids:prev.selected_course_ids.includes(id)?prev.selected_course_ids.filter((x)=>x!==id):[...prev.selected_course_ids,id]}));

  return <div className="modal-backdrop" onMouseDown={(e)=>{if(e.target===e.currentTarget)onClose();}}>
    <div className="modal-card academic-modal offering-generator-modal">
      <div className="section-title"><div><h2>Generate Course Offerings</h2><p>Create the current semester teaching/registration offerings directly from an existing programme curriculum.</p></div><button type="button" className="icon-button" onClick={onClose}><X size={19}/></button></div>
      <div className="form-grid">
        <label>Programme<select value={form.programme_id} onChange={set("programme_id")}><option value="">Select active programme…</option>{activeProgrammes.map((row)=><option key={row.id} value={row.id}>{row.code} — {row.name}</option>)}</select></label>
        <label>Level<select value={form.level_number} onChange={set("level_number")}>{[100,200,300,400,500,600,700].map((v)=><option key={v} value={v}>{v}</option>)}</select></label>
      </div>
      <div className="form-grid">
        <label>Academic year<select value={form.academic_year_id} onChange={set("academic_year_id")}><option value="">Select year…</option>{data.years.map((row)=><option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
        <label>Semester<select value={form.academic_period_id} onChange={set("academic_period_id")}><option value="">Select semester…</option>{periods.map((row)=><option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
      </div>
      <div className="form-grid">
        <label>Section<input value={form.section_code} onChange={set("section_code")} /></label>
        <label>Delivery mode<select value={form.delivery_mode} onChange={set("delivery_mode")}><option value="in_person">In person</option><option value="online">Online</option><option value="hybrid">Hybrid</option></select></label>
      </div>
      <div className="curriculum-course-picker">
        <div className="curriculum-picker-header"><div><strong>Curriculum Courses</strong><span>{form.selected_course_ids.length} selected</span></div><button type="button" className="secondary-button" disabled={!availableIds.length} onClick={()=>setForm((prev)=>({...prev,selected_course_ids:allSelected?[]:availableIds}))}>{allSelected?"Clear":"Select all available"}</button></div>
        {!form.programme_id||!form.academic_period_id?<div className="table-empty">Select programme, year and semester first.</div>:
        <div className="curriculum-course-checklist">
          {curriculumRows.map((row)=>{
            const exists=existingCourseIds.has(row.course_id);
            return <label key={row.id} className={`curriculum-course-option ${exists?"is-existing":""}`}><input type="checkbox" checked={exists||form.selected_course_ids.includes(row.course_id)} disabled={exists} onChange={()=>toggle(row.course_id)}/><span className="curriculum-course-copy"><strong>{row.course?.code}</strong><span>{row.course?.name}</span><small>{row.course?.credit_hours} credits • {row.course_category}{row.is_required?" • Required":""}</small></span>{exists&&<span className="status-pill active">Already offered</span>}</label>;
          })}
          {!curriculumRows.length&&<div className="table-empty">No curriculum courses match this programme, level and semester.</div>}
        </div>}
      </div>
      <div className="modal-actions"><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button type="button" className="primary-action" disabled={busy||!form.selected_course_ids.length} onClick={onGenerate}>{busy?"Generating…":`Generate ${form.selected_course_ids.length||""} Offering${form.selected_course_ids.length===1?"":"s"}`}</button></div>
    </div>
  </div>;
}

function AcademicTable({ entity, rows, busy, onEdit, onToggle, onCurrentYear, onCurrentPeriod }) {
  const headings = {
    years: ["Name", "Dates", "Status", "Current"],
    periods: ["Period", "Academic Year", "Dates", "Status", "Current"],
    faculties: ["Faculty", "Code", "Status"],
    schools: ["School", "Faculty", "Code", "Status"],
    departments: ["Department", "Parent", "Code", "Status"],
    programmes: ["Programme", "Department", "Award", "Duration", "Status"],
    courses: ["Course", "Department", "Credits", "Hours", "Status"],
    curriculum: ["Programme", "Course", "Level", "Semester", "Category"],
    offerings: ["Course", "Year / Semester", "Programme", "Level / Section", "Mode", "Status"],
    lecturers: ["Course Offering", "Lecturer", "Role", "Workload", "Primary"],
    schedules: ["Course Offering", "Day", "Time", "Venue", "Type"],
  }[entity];

  return (
    <div className="responsive-table">
      <table className="academic-table">
        <thead>
          <tr>
            {headings.map((heading) => <th key={heading}>{heading}</th>)}
            <th>Actions</th>
          </tr>
        </thead>

        <tbody>
          {rows.map((row) => (
            <tr key={row.id}>
              <AcademicCells entity={entity} row={row} />

              <td className="action-cell">
                <button type="button" className="table-action" onClick={() => onEdit(row)} disabled={!!busy}>
                  <Pencil size={14} /> Edit
                </button>

                {!["curriculum", "lecturers", "schedules"].includes(entity) && (
                  <button
                    type="button"
                    className={
                      entity === "offerings"
                        ? row.status === "open"
                          ? "table-action danger"
                          : "table-action"
                        : row.status === "active"
                          ? "table-action danger"
                          : "table-action"
                    }
                    onClick={() => onToggle(entity, row)}
                    disabled={!!busy}
                  >
                    {entity === "offerings" ? (
                      row.status === "open" ? <CircleOff size={14} /> : <CheckCircle2 size={14} />
                    ) : row.status === "active" ? (
                      <CircleOff size={14} />
                    ) : (
                      <CheckCircle2 size={14} />
                    )}

                    {entity === "offerings"
                      ? row.status === "open"
                        ? "Close"
                        : "Open"
                      : row.status === "active"
                        ? "Deactivate"
                        : "Activate"}
                  </button>
                )}

                {entity === "years" && !row.is_current && (
                  <button type="button" className="table-action" onClick={() => onCurrentYear(row)} disabled={!!busy}>
                    Set Current
                  </button>
                )}

                {entity === "periods" && !row.is_current && (
                  <button type="button" className="table-action" onClick={() => onCurrentPeriod(row)} disabled={!!busy}>
                    Set Current
                  </button>
                )}
              </td>
            </tr>
          ))}

          {!rows.length && (
            <tr>
              <td colSpan={headings.length + 1} className="table-empty">No records found.</td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
}

function AcademicCells({ entity, row }) {
  if (entity === "years") {
    return <><td><strong>{row.name}</strong></td><td>{row.start_date} → {row.end_date}</td><td><Status value={row.status} /></td><td>{row.is_current ? <span className="status-pill active">Current</span> : "—"}</td></>;
  }

  if (entity === "periods") {
    return <><td><strong>{row.name}</strong><div className="cell-note">{row.period_type} {row.period_number}</div></td><td>{row.academic_year?.name || "—"}</td><td>{row.start_date} → {row.end_date}</td><td><Status value={row.status} /></td><td>{row.is_current ? <span className="status-pill active">Current</span> : "—"}</td></>;
  }

  if (entity === "faculties") return <><td><strong>{row.name}</strong></td><td>{row.code}</td><td><Status value={row.status} /></td></>;
  if (entity === "schools") return <><td><strong>{row.name}</strong></td><td>{row.faculty?.name || "—"}</td><td>{row.code}</td><td><Status value={row.status} /></td></>;
  if (entity === "departments") return <><td><strong>{row.name}</strong></td><td>{row.school?.name || row.faculty?.name || "—"}</td><td>{row.code}</td><td><Status value={row.status} /></td></>;

  if (entity === "programmes") {
    return <><td><strong>{row.name}</strong><div className="cell-note">{row.code}</div></td><td>{row.department?.name || "—"}</td><td>{row.award_type || "—"}</td><td>{row.duration_years ? `${row.duration_years} years` : "—"}</td><td><Status value={row.status} /></td></>;
  }

  if (entity === "courses") {
    return <><td><strong>{row.code}</strong><div className="cell-note">{row.name}</div></td><td>{row.department?.name || "—"}</td><td>{row.credit_hours}</td><td>{row.lecture_hours}L / {row.practical_hours}P</td><td><Status value={row.status} /></td></>;
  }

  if (entity === "curriculum") {
    return <><td><strong>{row.programme?.code || "—"}</strong><div className="cell-note">{row.programme?.name || ""}</div></td><td><strong>{row.course?.code || "—"}</strong><div className="cell-note">{row.course?.name || ""}</div></td><td>{row.level_number}</td><td>{row.period_number}</td><td>{row.course_category}{row.is_required ? " • Required" : ""}</td></>;
  }

  if (entity === "offerings") {
    return <>
      <td><strong>{row.course?.code || "—"}</strong><div className="cell-note">{row.course?.name || ""}</div></td>
      <td>{row.academic_year?.name || "—"}<div className="cell-note">{row.academic_period?.name || "—"}</div></td>
      <td>{row.programme ? <><strong>{row.programme.code}</strong><div className="cell-note">{row.programme.name}</div></> : (row.department?.name || "Institution-wide")}</td>
      <td>{row.level_number || "—"} / {row.section_code}</td>
      <td>{row.delivery_mode}</td>
      <td><Status value={row.status} /></td>
    </>;
  }

  if (entity === "lecturers") {
    return <>
      <td>{offeringLabel(row.course_offering)}</td>
      <td><strong>{staffName(row.lecturer_profile)}</strong><div className="cell-note">{row.lecturer_profile?.specialization || ""}</div></td>
      <td>{row.allocation_role}</td>
      <td>{row.workload_percentage}%</td>
      <td>{row.is_primary ? <span className="status-pill active">Primary</span> : "—"}</td>
    </>;
  }

  const day = DAYS.find(([value]) => value === row.day_of_week)?.[1] || row.day_of_week;
  return <>
    <td>{offeringLabel(row.course_offering)}</td>
    <td>{day}</td>
    <td>{String(row.start_time || "").slice(0, 5)} – {String(row.end_time || "").slice(0, 5)}</td>
    <td>{row.venue || "—"}</td>
    <td>{row.schedule_type}</td>
  </>;
}

function Status({ value }) {
  return <span className={`status-pill ${value}`}>{value}</span>;
}

function CommonFields({ form, set, status }) {
  return <>
    <div className="form-grid">
      <label>Name<input required value={form.name} onChange={set("name")} /></label>
      <label>Code<input required value={form.code} onChange={set("code")} /></label>
    </div>
    <label>Description<textarea value={form.description || ""} onChange={set("description")} rows="3" /></label>
    {status}
  </>;
}

function AcademicForm({ entity, form, setForm, data, activeProgrammes = [], curriculumSelectedCourseIds = [], setCurriculumSelectedCourseIds = () => {}, mode }) {
  const set = (key) => (e) =>
    setForm({
      ...form,
      [key]: e.target.type === "checkbox" ? e.target.checked : e.target.value,
    });

  const status = (
    <label>
      Status
      <select value={form.status || "active"} onChange={set("status")}>
        <option value="planned">Planned</option>
        <option value="active">Active</option>
        <option value="inactive">Inactive</option>
        <option value="closed">Closed</option>
      </select>
    </label>
  );

  if (entity === "years") return <>
    <label>Academic year name<input required value={form.name} onChange={set("name")} placeholder="2026/2027" /></label>
    <div className="form-grid"><label>Start date<input type="date" required value={form.start_date} onChange={set("start_date")} /></label><label>End date<input type="date" required value={form.end_date} onChange={set("end_date")} /></label></div>
    {status}
  </>;

  if (entity === "periods") return <>
    <label>Academic year<select required value={form.academic_year_id} onChange={set("academic_year_id")}><option value="">Select year…</option>{data.years.map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
    <div className="form-grid"><label>Name<input required value={form.name} onChange={set("name")} placeholder="Semester 1" /></label><label>Period number<input type="number" min="1" required value={form.period_number} onChange={set("period_number")} /></label></div>
    <label>Period type<select value={form.period_type} onChange={set("period_type")}><option value="semester">Semester</option><option value="trimester">Trimester</option><option value="term">Term</option></select></label>
    <div className="form-grid"><label>Start date<input type="date" required value={form.start_date} onChange={set("start_date")} /></label><label>End date<input type="date" required value={form.end_date} onChange={set("end_date")} /></label></div>
    <div className="form-grid"><label>Registration opens<input type="date" value={form.registration_start || ""} onChange={set("registration_start")} /></label><label>Registration closes<input type="date" value={form.registration_end || ""} onChange={set("registration_end")} /></label></div>
    {status}
  </>;

  if (entity === "faculties") return <CommonFields form={form} set={set} status={status} />;

  if (entity === "schools") return <>
    <label>Faculty<select value={form.faculty_id || ""} onChange={set("faculty_id")}><option value="">No faculty / standalone</option>{data.faculties.map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
    <CommonFields form={form} set={set} status={status} />
  </>;

  if (entity === "departments") return <>
    <label>School<select value={form.school_id || ""} onChange={set("school_id")}><option value="">No school / direct faculty department</option>{data.schools.map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
    <label>Faculty<select value={form.faculty_id || ""} onChange={set("faculty_id")}><option value="">Select faculty…</option>{data.faculties.map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
    <CommonFields form={form} set={set} status={status} />
  </>;

  if (entity === "programmes") return <>
    <label>Department<select value={form.department_id || ""} onChange={set("department_id")}><option value="">Select department…</option>{data.departments.map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
    <div className="form-grid"><label>Programme name<input required value={form.name} onChange={set("name")} /></label><label>Code<input required value={form.code} onChange={set("code")} /></label></div>
    <div className="form-grid"><label>Award type<input value={form.award_type || ""} onChange={set("award_type")} placeholder="BSc, BA, MSc…" /></label><label>Duration (years)<input type="number" min="0" step="0.5" value={form.duration_years || ""} onChange={set("duration_years")} /></label></div>
    <label>Total credits<input type="number" min="0" step="0.5" value={form.total_credits || ""} onChange={set("total_credits")} /></label>
    <label>Description<textarea rows="3" value={form.description || ""} onChange={set("description")} /></label>
    {status}
  </>;

  if (entity === "courses") return <>
    <label>Department<select value={form.department_id || ""} onChange={set("department_id")}><option value="">Institution-wide / no department</option>{data.departments.map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
    <div className="form-grid"><label>Course code<input required value={form.code} onChange={set("code")} /></label><label>Course name<input required value={form.name} onChange={set("name")} /></label></div>
    <label>Course type<select value={form.course_type} onChange={set("course_type")}><option value="course">Course</option><option value="project">Project</option><option value="internship">Internship</option><option value="thesis">Thesis</option></select></label>
    <div className="form-grid academic-three"><label>Credits<input type="number" min="0" step="0.5" value={form.credit_hours} onChange={set("credit_hours")} /></label><label>Lecture hours<input type="number" min="0" step="0.5" value={form.lecture_hours} onChange={set("lecture_hours")} /></label><label>Practical hours<input type="number" min="0" step="0.5" value={form.practical_hours} onChange={set("practical_hours")} /></label></div>
    <label>Description<textarea rows="3" value={form.description || ""} onChange={set("description")} /></label>
    {status}
  </>;

  if (entity === "curriculum") {
    const eligibleCourses = data.courses.filter((row) => row.status === "active");
    const existingCourseIds = new Set(
      (data.curriculum || [])
        .filter((row) =>
          row.programme_id === form.programme_id &&
          Number(row.level_number) === Number(form.level_number) &&
          Number(row.period_number) === Number(form.period_number)
        )
        .map((row) => row.course_id)
    );
    const toggleCourse = (id) => {
      setCurriculumSelectedCourseIds((prev) =>
        prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]
      );
    };
    const availableIds = eligibleCourses.filter(c=>!existingCourseIds.has(c.id)).map(c=>c.id);
    const allAvailableSelected = availableIds.length>0 && availableIds.every(id=>curriculumSelectedCourseIds.includes(id));

    return <>
      <label>Programme
        <select required value={form.programme_id} onChange={(e)=>{set("programme_id")(e);setCurriculumSelectedCourseIds([]);}}>
          <option value="">Select active programme…</option>
          {activeProgrammes.map((row) => <option key={row.id} value={row.id}>{row.code} — {row.name}</option>)}
        </select>
        {!activeProgrammes.length && <small className="form-help error-text">No usable programmes were loaded. Check programme status values in Academics → Programmes.</small>}
      </label>
      <div className="form-grid"><label>Level<select value={form.level_number} onChange={(e)=>{set("level_number")(e);setCurriculumSelectedCourseIds([]);}}>{[100,200,300,400,500,600,700].map((level) => <option key={level} value={level}>{level}</option>)}</select></label><label>Semester / period number<input type="number" min="1" required value={form.period_number} onChange={(e)=>{set("period_number")(e);setCurriculumSelectedCourseIds([]);}} /></label></div>
      <div className="form-grid"><label>Course category<select value={form.course_category} onChange={set("course_category")}><option value="core">Core</option><option value="elective">Elective</option><option value="required">Required</option><option value="optional">Optional</option></select></label><label className="checkbox-row curriculum-required-check"><input type="checkbox" checked={Boolean(form.is_required)} onChange={set("is_required")} />Required for programme completion</label></div>

      {mode === "edit" ? (
        <label>Course<select required value={form.course_id} onChange={set("course_id")}><option value="">Select course…</option>{eligibleCourses.map((row) => <option key={row.id} value={row.id}>{row.code} — {row.name}</option>)}</select></label>
      ) : (
        <div className="curriculum-course-picker">
          <div className="curriculum-picker-header">
            <div><strong>Select Courses</strong><span>{curriculumSelectedCourseIds.length} selected</span></div>
            <div>
              <button type="button" className="secondary-button" disabled={!form.programme_id||!availableIds.length} onClick={()=>setCurriculumSelectedCourseIds(allAvailableSelected?[]:availableIds)}>{allAvailableSelected?"Clear":"Select all available"}</button>
            </div>
          </div>
          {!form.programme_id ? <div className="table-empty">Select a programme first.</div> :
          <div className="curriculum-course-checklist">
            {eligibleCourses.map((course)=>{
              const already=existingCourseIds.has(course.id);
              const checked=already||curriculumSelectedCourseIds.includes(course.id);
              return <label key={course.id} className={`curriculum-course-option ${already?"is-existing":""}`}>
                <input type="checkbox" checked={checked} disabled={already} onChange={()=>toggleCourse(course.id)}/>
                <span className="curriculum-course-copy"><strong>{course.code}</strong><span>{course.name}</span><small>{course.credit_hours} credit{Number(course.credit_hours)===1?"":"s"}{course.department?.name?` • ${course.department.name}`:""}</small></span>
                {already&&<span className="status-pill active">Already added</span>}
              </label>;
            })}
            {!eligibleCourses.length&&<div className="table-empty">No active courses are available.</div>}
          </div>}
        </div>
      )}
    </>;
  }

  if (entity === "offerings") {
    const periods = form.academic_year_id
      ? data.periods.filter((row) => row.academic_year_id === form.academic_year_id)
      : data.periods;

    return <>
      <label>Course<select required value={form.course_id} onChange={set("course_id")}><option value="">Select course…</option>{data.courses.map((row) => <option key={row.id} value={row.id}>{row.code} — {row.name}</option>)}</select></label>
      <div className="form-grid">
        <label>Academic year<select required value={form.academic_year_id} onChange={set("academic_year_id")}><option value="">Select year…</option>{data.years.map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
        <label>Semester<select required value={form.academic_period_id} onChange={set("academic_period_id")}><option value="">Select semester…</option>{periods.map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
      </div>
      <div className="form-grid">
        <label>Programme<select value={form.programme_id || ""} onChange={set("programme_id")}><option value="">Institution-wide / no programme</option>{activeProgrammes.map((row) => <option key={row.id} value={row.id}>{row.code} — {row.name}</option>)}</select></label>
        <label>Department<select value={form.department_id || ""} onChange={set("department_id")}><option value="">No department</option>{data.departments.map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
      </div>
      <div className="form-grid academic-three">
        <label>Level<input type="number" min="100" step="100" value={form.level_number || ""} onChange={set("level_number")} /></label>
        <label>Section<input required value={form.section_code} onChange={set("section_code")} /></label>
        <label>Capacity<input type="number" min="1" value={form.capacity || ""} onChange={set("capacity")} /></label>
      </div>
      <div className="form-grid">
        <label>
          Delivery mode
          <select value={form.delivery_mode} onChange={set("delivery_mode")}>
            <option value="in_person">In person</option>
            <option value="online">Online</option>
            <option value="hybrid">Hybrid</option>
            <option value="other">Other</option>
          </select>
        </label>

        <label>
          Offering status
          <select value={form.status} onChange={set("status")}>
            <option value="planned">Planned</option>
            <option value="open">Open</option>
            <option value="closed">Closed</option>
            <option value="cancelled">Cancelled</option>
            <option value="completed">Completed</option>
          </select>
        </label>
      </div>
      <label className="checkbox-row"><input type="checkbox" checked={Boolean(form.registration_open)} onChange={set("registration_open")} />Registration open</label>
      <label>Notes<textarea rows="3" value={form.notes || ""} onChange={set("notes")} /></label>
    </>;
  }

  if (entity === "lecturers") return <>
    <label>Course offering<select required value={form.course_offering_id} onChange={set("course_offering_id")}><option value="">Select course offering…</option>{data.offerings.map((row) => <option key={row.id} value={row.id}>{offeringLabel(row)}</option>)}</select></label>
    <label>Lecturer<select required value={form.lecturer_profile_id} onChange={set("lecturer_profile_id")}><option value="">Select lecturer…</option>{data.lecturerProfiles.map((row) => <option key={row.id} value={row.id}>{staffName(row)}</option>)}</select></label>
    <div className="form-grid">
      <label>Allocation role<select value={form.allocation_role} onChange={set("allocation_role")}><option value="lecturer">Lecturer</option><option value="co_lecturer">Co-lecturer</option><option value="tutor">Tutor</option><option value="supervisor">Supervisor</option></select></label>
      <label>Workload %<input type="number" min="0" max="100" step="1" value={form.workload_percentage} onChange={set("workload_percentage")} /></label>
    </div>
    <label className="checkbox-row"><input type="checkbox" checked={Boolean(form.is_primary)} onChange={set("is_primary")} />Primary lecturer for this offering</label>
  </>;

  return <>
    <label>Course offering<select required value={form.course_offering_id} onChange={set("course_offering_id")}><option value="">Select course offering…</option>{data.offerings.map((row) => <option key={row.id} value={row.id}>{offeringLabel(row)}</option>)}</select></label>
    <div className="form-grid">
      <label>Day<select value={form.day_of_week} onChange={set("day_of_week")}>{DAYS.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
      <label>Type<select value={form.schedule_type} onChange={set("schedule_type")}><option value="lecture">Lecture</option><option value="practical">Practical</option><option value="tutorial">Tutorial</option><option value="seminar">Seminar</option></select></label>
    </div>
    <div className="form-grid">
      <label>Start time<input type="time" required value={form.start_time} onChange={set("start_time")} /></label>
      <label>End time<input type="time" required value={form.end_time} onChange={set("end_time")} /></label>
    </div>
    <label>Venue<input value={form.venue || ""} onChange={set("venue")} placeholder="Room / Lab / Online" /></label>
  </>;
}
