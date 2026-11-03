export default function DashboardSectionMenu({ groups = [], activeKey, onSelect, className = "" }) {
  return (
    <div className={`dashboard-section-menu ${className}`.trim()}>
      {groups.map((group) => (
        <section className="dashboard-section-group" key={group.label || group.key}>
          {group.label ? <div className="dashboard-section-group-label">{group.label}</div> : null}
          <div className="dashboard-section-actions">
            {(group.items || []).map(({ key, label, icon: Icon, subitem }) => (
              <button
                type="button"
                key={key}
                className={`${activeKey === key ? "dashboard-section-link active" : "dashboard-section-link"}${subitem ? " dashboard-section-subitem" : ""}`}
                onClick={() => onSelect?.(key)}
              >
                {Icon ? <Icon size={16} /> : null}
                <span>{label}</span>
              </button>
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}
