import { useState } from "react";
import { supabase } from "../../lib/supabase";
import { acceptOwnInvitation } from "../../services/userManagement";

export default function ResetPassword() {
  const [password, setPassword] = useState("");
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(e) {
    e.preventDefault();
    setBusy(true);
    setMsg("");

    const { error: passwordError } = await supabase.auth.updateUser({ password });

    if (passwordError) {
      setMsg(passwordError.message);
      setBusy(false);
      return;
    }

    // Safe for both invitation and ordinary password-reset flows.
    // If this session came from a UniMIS invitation, the matching invitation
    // becomes accepted. Otherwise the RPC simply returns false.
    const { error: invitationError } = await acceptOwnInvitation();

    if (invitationError) {
      setMsg(`Password updated, but invitation status could not be finalized: ${invitationError.message}`);
      setBusy(false);
      return;
    }

    setMsg("Password updated. Your account is active and you can now sign in.");
    setBusy(false);
  }

  return (
    <div className="card">
      <h2>New password</h2>
      <form onSubmit={submit}>
        <label>
          Password
          <input
            type="password"
            minLength="8"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
        </label>
        <button disabled={busy}>
          {busy ? "Updating..." : "Update password"}
        </button>
      </form>
      {msg && <p>{msg}</p>}
    </div>
  );
}
