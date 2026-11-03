import { Navigate } from "react-router-dom";
import { useAuth } from "../../contexts/AuthContext";
import { useUserContext } from "../../contexts/UserContext";

export default function PortalRedirect() {
  const { user } = useAuth();
  const u = useUserContext();

  if (u.loading) {
    return <div className="page-loader">Loading your portal...</div>;
  }

  if (u.error) {
    return (
      <div className="empty-state">
        <div>
          <h2>Unable to load your account</h2>
          <p>{u.error}</p>
        </div>
      </div>
    );
  }

  if (u.platformOperator) return <Navigate to="/platform" replace />;

  // Applicant accounts deliberately do not need an institution_users role.
  // If one reaches /dashboard, route it back to the Applicant Portal.
  if (user?.user_metadata?.account_type === "applicant") {
    return <Navigate to="/apply" replace />;
  }

  if (!u.memberships.length) {
    return (
      <div className="empty-state">
        <div>
          <h2>Account not assigned</h2>
          <p>
            Your login works, but this account has not yet been assigned a
            UniMIS role.
          </p>
        </div>
      </div>
    );
  }

  return <Navigate to={u.defaultPortal} replace />;
}
