import { createContext, useContext, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";
import { useUserContext } from "./UserContext";

const WorkflowContext = createContext(null);

export const WORKFLOW_STEPS = [
  { key: "institution_configured", label: "Institution Setup", description: "University identity, contacts and core settings are configured." },
  { key: "academic_structure_configured", label: "Academic Structure", description: "Academic year, semesters, faculties, departments and programmes are configured." },
  { key: "admissions_ready", label: "Admissions Ready", description: "Admission settings and intake structure are ready for applications." },
  { key: "student_records_ready", label: "Student Records Ready", description: "Admitted students can be maintained as active student records." },
  { key: "teaching_ready", label: "Teaching & Attendance Ready", description: "Courses, offerings and lecturer allocations are ready." },
  { key: "results_ready", label: "Results Ready", description: "Assessment and grading setup is ready for results processing." },
];

export function WorkflowProvider({ children }) {
  const { institutionId, loading: userLoading } = useUserContext();
  const [status, setStatus] = useState({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  async function refresh() {
    if (!institutionId) {
      setStatus({});
      setLoading(false);
      return;
    }
    setLoading(true);
    const { data, error: queryError } = await supabase
      .from("institution_workflow_status")
      .select("step_key,is_complete,completed_at")
      .eq("institution_id", institutionId);

    if (queryError) {
      setError(queryError.message);
      setLoading(false);
      return;
    }
    setStatus(Object.fromEntries((data || []).map((row) => [row.step_key, row])));
    setError("");
    setLoading(false);
  }

  useEffect(() => {
    if (!userLoading) refresh();
  }, [institutionId, userLoading]);

  const isComplete = (key) => Boolean(status[key]?.is_complete);
  const completedCount = useMemo(() => WORKFLOW_STEPS.filter((s) => isComplete(s.key)).length, [status]);

  return (
    <WorkflowContext.Provider value={{ status, loading, error, isComplete, completedCount, totalSteps: WORKFLOW_STEPS.length, refresh }}>
      {children}
    </WorkflowContext.Provider>
  );
}

export const useWorkflow = () => useContext(WorkflowContext);
