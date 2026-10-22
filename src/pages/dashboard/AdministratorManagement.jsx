import Toast from "../../components/Toast";
import { useCallback, useEffect, useState } from "react";
import { ShieldCheck, UserPlus, RefreshCw, UserCheck, UserX } from "lucide-react";
import { supabase } from "../../lib/supabase";

export default function AdministratorManagement() {
  const [admins, setAdmins] = useState([]);
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  const loadAdmins = useCallback(async () => {
    setLoading(true); setError("");
    const { data, error: rpcError } = await supabase.rpc("owner_list_administrators");
    if (rpcError) setError(rpcError.message);
    else setAdmins(data || []);
    setLoading(false);
  }, []);

  useEffect(() => { loadAdmins(); }, [loadAdmins]);

  async function assignAdmin(e) {
    e.preventDefault();
    const cleanEmail = email.trim().toLowerCase();
    if (!cleanEmail) return;
    setSaving(true); setError(""); setMessage("");
    const { error: rpcError } = await supabase.rpc("owner_assign_admin_by_email", { target_email: cleanEmail });
    if (rpcError) setError(rpcError.message);
    else {
      setMessage(`${cleanEmail} has been assigned the Administrator role.`);
      setEmail("");
      await loadAdmins();
    }
    setSaving(false);
  }

  async function setStatus(userId, status) {
    setError(""); setMessage("");
    const { error: rpcError } = await supabase.rpc("owner_set_admin_status", { target_user_id: userId, new_status: status });
    if (rpcError) setError(rpcError.message);
    else { setMessage(`Administrator ${status === "active" ? "activated" : "deactivated"}.`); await loadAdmins(); }
  }

  return (
    <section>
      <div className="page-heading">
        <span className="eyebrow">System oversight</span>
        <h1>Administrator Management</h1>
        <p>The Owner assigns trusted registered users as Administrators. Administrators run the day-to-day UniMIS.</p>
      </div>

      <div className="notice-panel"><ShieldCheck size={20}/><strong>Owner boundary</strong><span>This page manages Administrator access only. Routine university operations remain in the Admin portal.</span></div>

      <div className="management-card">
        <div className="section-title"><div><h2>Assign Administrator</h2><p>The person must first create a UniMIS login account. Enter the same email used during registration.</p></div><UserPlus size={24}/></div>
        <form className="inline-form" onSubmit={assignAdmin}>
          <input type="email" value={email} onChange={(e)=>setEmail(e.target.value)} placeholder="administrator@university.edu" required />
          <button type="submit" disabled={saving}>{saving ? "Assigning…" : "Assign Admin"}</button>
        </form>
        <Toast message={error||message} type={error?"error":"success"} onClose={()=>{setError("");setMessage("")}}/>
      </div>

      <div className="management-card">
        <div className="section-title"><div><h2>Current Administrators</h2><p>Accounts currently assigned to the Administrator role.</p></div><button className="secondary-button" onClick={loadAdmins}><RefreshCw size={17}/> Refresh</button></div>
        {loading ? <div className="table-empty">Loading administrators…</div> : admins.length === 0 ? <div className="table-empty">No Administrator has been assigned yet.</div> : (
          <div className="responsive-table"><table><thead><tr><th>Name</th><th>Email</th><th>Status</th><th>Primary</th><th>Action</th></tr></thead><tbody>
            {admins.map((a)=><tr key={a.user_id}><td><strong>{a.display_name || "Unnamed user"}</strong></td><td>{a.email}</td><td><span className={`status-pill ${a.status}`}>{a.status}</span></td><td>{a.is_primary ? "Yes" : "No"}</td><td>{a.status === "active" ? <button className="table-action danger" onClick={()=>setStatus(a.user_id,"inactive")}><UserX size={16}/> Deactivate</button> : <button className="table-action" onClick={()=>setStatus(a.user_id,"active")}><UserCheck size={16}/> Activate</button>}</td></tr>)}
          </tbody></table></div>
        )}
      </div>
    </section>
  );
}
