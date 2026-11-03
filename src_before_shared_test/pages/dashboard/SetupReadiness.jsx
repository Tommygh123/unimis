import { CheckCircle2, Circle, LockKeyhole } from "lucide-react";
import { WORKFLOW_STEPS, useWorkflow } from "../../contexts/WorkflowContext";

export default function SetupReadiness() {
  const { isComplete, completedCount, totalSteps, loading, error } = useWorkflow();
  const percent = Math.round((completedCount / totalSteps) * 100);

  return (
    <section>
      <div className="page-heading">
        <span className="eyebrow">Implementation workflow</span>
        <h1>Setup Readiness</h1>
        <p>UniMIS unlocks operational modules as their prerequisite setup is completed.</p>
      </div>

      <div className="readiness-summary">
        <div><strong>{loading ? "…" : `${percent}%`}</strong><span>Overall readiness</span></div>
        <div><strong>{completedCount}/{totalSteps}</strong><span>Setup stages complete</span></div>
      </div>

      {error && <div className="workflow-error">{error}</div>}

      <div className="workflow-list">
        {WORKFLOW_STEPS.map((step, index) => {
          const complete = isComplete(step.key);
          const previousComplete = index === 0 || isComplete(WORKFLOW_STEPS[index - 1].key);
          return (
            <div className={`workflow-step${complete ? " complete" : ""}`} key={step.key}>
              <div className="workflow-step-icon">
                {complete ? <CheckCircle2 size={24} /> : previousComplete ? <Circle size={24} /> : <LockKeyhole size={22} />}
              </div>
              <div>
                <h3>{step.label}</h3>
                <p>{step.description}</p>
                <span>{complete ? "Complete" : previousComplete ? "Current setup stage" : "Waiting for prerequisite"}</span>
              </div>
            </div>
          );
        })}
      </div>
      <p className="workflow-note">Readiness will be updated by each setup module as we build it. It is not intended as a manual bypass switch.</p>
    </section>
  );
}
