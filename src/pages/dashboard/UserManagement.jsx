import Toast from "../../components/Toast";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  UserPlus,
  RefreshCw,
  Search,
  Users,
  Mail,
  ShieldCheck,
  UserCheck,
  UserX,
  RotateCcw,
  Ban,
  X,
} from "lucide-react";

import { useUserContext } from "../../contexts/UserContext";

import {
  listInstitutionUsers,
  listInvitations,
  listAssignableRoles,
  createInvitation,
  refreshInvitationRecord,
  revokeInvitation,
  changeUserRole,
  setUserStatus,
} from "../../services/userManagement";

const emptyForm = {
  email: "",
  first_name: "",
  middle_name: "",
  last_name: "",
  role_id: "",
};

export default function UserManagement() {
  const { institutionId } = useUserContext();

  const [users, setUsers] = useState([]);
  const [invites, setInvites] = useState([]);
  const [roles, setRoles] = useState([]);

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState("");

  const [error, setError] = useState("");
  const [message, setMessage] = useState("");

  const [query, setQuery] = useState("");
  const [roleFilter, setRoleFilter] = useState("");

  const [showInvite, setShowInvite] = useState(false);

  const [form, setForm] = useState(emptyForm);

  const load = useCallback(async () => {
    if (!institutionId) {
      setLoading(false);
      return;
    }

    setLoading(true);
    setError("");

    const [usersResult, invitationsResult, rolesResult] =
      await Promise.all([
        listInstitutionUsers(institutionId),
        listInvitations(institutionId),
        listAssignableRoles(institutionId),
      ]);

    const firstError =
      usersResult.error ||
      invitationsResult.error ||
      rolesResult.error;

    if (firstError) {
      setError(firstError.message);
    } else {
      setUsers(usersResult.data || []);
      setInvites(invitationsResult.data || []);
      setRoles(rolesResult.data || []);
    }

    setLoading(false);
  }, [institutionId]);

  useEffect(() => {
    load();
  }, [load]);

  const filteredUsers = useMemo(() => {
    const search = query.trim().toLowerCase();

    return users.filter((user) => {
      const searchableText = [
        user.display_name,
        user.email,
        user.first_name,
        user.middle_name,
        user.last_name,
        user.role_name,
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();

      const matchesSearch =
        !search || searchableText.includes(search);

      const matchesRole =
        !roleFilter || user.role_code === roleFilter;

      return matchesSearch && matchesRole;
    });
  }, [users, query, roleFilter]);

  async function submitInvite(e) {
    e.preventDefault();

    if (!institutionId) {
      setError("Institution could not be determined.");
      return;
    }

    setBusy("invite");
    setError("");
    setMessage("");

    try {
      const { data, error: inviteError } =
        await createInvitation({
          p_institution_id: institutionId,
          p_email: form.email.trim().toLowerCase(),
          p_role_id: form.role_id,
          p_first_name: form.first_name || null,
          p_middle_name: form.middle_name || null,
          p_last_name: form.last_name || null,
        });

      if (inviteError) {
        throw inviteError;
      }

      if (data?.ok === false) {
        throw new Error(
          data.error || "Unable to send invitation."
        );
      }

      setMessage(
        "Auth invitation sent successfully. Check Mailpit during local development."
      );

      setForm(emptyForm);
      setShowInvite(false);

      await load();
    } catch (err) {
      setError(
        err?.message ||
          "Unable to create the invitation."
      );
    } finally {
      setBusy("");
    }
  }

  async function runAction(key, fn, successMessage) {
    setBusy(key);
    setError("");
    setMessage("");

    try {
      const { error: actionError } = await fn();

      if (actionError) {
        throw actionError;
      }

      setMessage(successMessage);

      await load();
    } catch (err) {
      setError(
        err?.message ||
          "Unable to complete this action."
      );
    } finally {
      setBusy("");
    }
  }

  async function handleRoleChange(user, roleId) {
    if (!roleId || roleId === user.role_id) {
      return;
    }

    await runAction(
      `role-${user.institution_user_id}`,
      () =>
        changeUserRole(
          user.institution_user_id,
          roleId
        ),
      "User role updated successfully."
    );
  }

  async function handleStatusChange(user, status) {
    await runAction(
      `status-${user.institution_user_id}`,
      () =>
        setUserStatus(
          user.institution_user_id,
          status
        ),
      status === "active"
        ? "User activated successfully."
        : "User deactivated successfully."
    );
  }

  async function handleRefreshInvitation(invitation) {
    await runAction(
      `refresh-${invitation.id}`,
      () =>
        refreshInvitationRecord(invitation),
      "Invitation sent/refreshed successfully."
    );
  }

  async function handleRevokeInvitation(invitationId) {
    await runAction(
      `revoke-${invitationId}`,
      () =>
        revokeInvitation(invitationId),
      "Invitation revoked successfully."
    );
  }

  const activeUserCount = users.filter(
    (user) => user.status === "active"
  ).length;

  const pendingInvitationCount =
    invites.filter(
      (invite) => invite.status === "pending"
    ).length;

  return (
    <section>
      <div className="page-heading user-page-heading">
        <div>
          <span className="eyebrow">
            Administration
          </span>

          <h1>User Management</h1>

          <p>
            Manage login access, operational roles, account status and invitations.
            Student and parent accounts are provisioned through Admissions/Student
            Management; staff master records are maintained through HR/Staff Management.
          </p>
        </div>

        <button
          type="button"
          className="primary-action"
          onClick={() => {
            setError("");
            setMessage("");
            setShowInvite(true);
          }}
        >
          <UserPlus size={18} />
          Invite User
        </button>
      </div>

      <Toast message={error||message} type={error?"error":"success"} onClose={()=>{setError("");setMessage("")}}/>

      <div className="user-stats">
        <div>
          <Users />

          <span>Active users</span>

          <strong>
            {activeUserCount}
          </strong>
        </div>

        <div>
          <Mail />

          <span>
            Pending invitations
          </span>

          <strong>
            {pendingInvitationCount}
          </strong>
        </div>

        <div>
          <ShieldCheck />

          <span>
            Operational roles
          </span>

          <strong>
            {roles.length}
          </strong>
        </div>
      </div>

      <div className="management-card">
        <div className="section-title">
          <div>
            <h2>University Users</h2>

            <p>
              Search users, change roles and
              control institutional access.
            </p>
          </div>

          <button
            type="button"
            className="secondary-button"
            onClick={load}
            disabled={loading}
          >
            <RefreshCw
              size={17}
              className={
                loading ? "spin" : ""
              }
            />

            Refresh
          </button>
        </div>

        <div className="user-toolbar">
          <label className="search-box">
            <Search size={17} />

            <input
              value={query}
              onChange={(e) =>
                setQuery(e.target.value)
              }
              placeholder="Search name, email, ID or role..."
            />
          </label>

          <select
            value={roleFilter}
            onChange={(e) =>
              setRoleFilter(e.target.value)
            }
          >
            <option value="">
              All roles
            </option>

            {roles.map((role) => (
              <option
                key={role.id}
                value={role.code}
              >
                {role.name}
              </option>
            ))}
          </select>
        </div>

        {loading ? (
          <div className="table-empty">
            Loading users...
          </div>
        ) : (
          <div className="responsive-table">
            <table>
              <thead>
                <tr>
                  <th>User</th>
                  <th>Role</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>

              <tbody>
                {filteredUsers.map((user) => {
                  const fullName =
                    user.display_name ||
                    [
                      user.first_name,
                      user.middle_name,
                      user.last_name,
                    ]
                      .filter(Boolean)
                      .join(" ") ||
                    user.email ||
                    "Unnamed user";

                  const userBusy =
                    busy.includes(
                      user.institution_user_id
                    );
                  const isOwner = user.role_code === "owner";

                  return (
                    <tr
                      key={
                        user.institution_user_id
                      }
                    >
                      <td>
                        <strong>{fullName}</strong>
                        {user.email && user.email !== fullName && (
                          <div className="user-email">{user.email}</div>
                        )}
                      </td>

                      <td>
                        {isOwner ? (
                          <span className="owner-role-label">Owner</span>
                        ) : (
                          <select
                            className="table-select"
                            value={user.role_id || ""}
                            disabled={userBusy}
                            onChange={(e) =>
                              handleRoleChange(user, e.target.value)
                            }
                          >
                            {roles.map((role) => (
                              <option key={role.id} value={role.id}>
                                {role.name}
                              </option>
                            ))}
                          </select>
                        )}
                      </td>

                      <td>
                        <span
                          className={`status-pill ${user.status}`}
                        >
                          {user.status}
                        </span>
                      </td>

                      <td>
                        {isOwner ? (
                          <span className="owner-protected">Protected</span>
                        ) : user.status === "active" ? (
                          <button
                            type="button"
                            className="table-action danger"
                            disabled={!!busy}
                            onClick={() => handleStatusChange(user, "inactive")}
                          >
                            <UserX size={15} />
                            Deactivate
                          </button>
                        ) : (
                          <button
                            type="button"
                            className="table-action"
                            disabled={!!busy}
                            onClick={() => handleStatusChange(user, "active")}
                          >
                            <UserCheck size={15} />
                            Activate
                          </button>
                        )}
                      </td>
                    </tr>
                  );
                })}

                {!filteredUsers.length && (
                  <tr>
                    <td
                      colSpan="4"
                      className="table-empty"
                    >
                      No users match the
                      current filter.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="management-card">
        <div className="section-title">
          <div>
            <h2>Invitations</h2>

            <p>
              Pending, accepted,
              expired and revoked
              invitations.
            </p>
          </div>
        </div>

        <div className="responsive-table">
          <table>
            <thead>
              <tr>
                <th>Email</th>
                <th>Role</th>
                <th>Status</th>
                <th>Expires</th>
                <th>Actions</th>
              </tr>
            </thead>

            <tbody>
              {invites.map((invite) => (
                <tr key={invite.id}>
                  <td>
                    <strong>
                      {invite.email}
                    </strong>
                  </td>

                  <td>
                    {invite.role?.name ||
                      "—"}
                  </td>

                  <td>
                    <span
                      className={`status-pill ${invite.status}`}
                    >
                      {invite.status}
                    </span>
                  </td>

                  <td>
                    {invite.expires_at
                      ? new Date(
                          invite.expires_at
                        ).toLocaleDateString()
                      : "—"}
                  </td>

                  <td className="action-cell">
                    {invite.status ===
                      "pending" && (
                      <button
                        type="button"
                        className="table-action"
                        disabled={
                          !!busy
                        }
                        onClick={() =>
                          handleRefreshInvitation(
                            invite
                          )
                        }
                      >
                        <RotateCcw
                          size={15}
                        />

                        Send / Refresh
                      </button>
                    )}

                    {invite.status ===
                      "pending" && (
                      <button
                        type="button"
                        className="table-action danger"
                        disabled={
                          !!busy
                        }
                        onClick={() =>
                          handleRevokeInvitation(
                            invite.id
                          )
                        }
                      >
                        <Ban
                          size={15}
                        />

                        Revoke
                      </button>
                    )}
                  </td>
                </tr>
              ))}

              {!invites.length && (
                <tr>
                  <td
                    colSpan="5"
                    className="table-empty"
                  >
                    No invitations yet.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {showInvite && (
        <div
          className="modal-backdrop"
          onMouseDown={(e) => {
            if (
              e.target ===
              e.currentTarget
            ) {
              setShowInvite(false);
            }
          }}
        >
          <div className="modal-card">
            <div className="section-title">
              <div>
                <h2>Invite User</h2>

                <p>
                  Create a UniMIS login/access account for an operational user.
                  Student and parent accounts are created from their business workflows.
                </p>
              </div>

              <button
                type="button"
                className="icon-button"
                onClick={() =>
                  setShowInvite(false)
                }
                aria-label="Close invitation form"
              >
                <X size={19} />
              </button>
            </div>

            <form
              className="user-form"
              onSubmit={submitInvite}
            >
              <label>
                Email

                <input
                  type="email"
                  required
                  value={form.email}
                  onChange={(e) =>
                    setForm({
                      ...form,
                      email:
                        e.target.value,
                    })
                  }
                />
              </label>

              <div className="form-grid">
                <label>
                  First name

                  <input
                    value={
                      form.first_name
                    }
                    onChange={(e) =>
                      setForm({
                        ...form,
                        first_name:
                          e.target.value,
                      })
                    }
                  />
                </label>

                <label>
                  Last name

                  <input
                    value={
                      form.last_name
                    }
                    onChange={(e) =>
                      setForm({
                        ...form,
                        last_name:
                          e.target.value,
                      })
                    }
                  />
                </label>
              </div>

              <label>
                Middle name

                <input
                  value={
                    form.middle_name
                  }
                  onChange={(e) =>
                    setForm({
                      ...form,
                      middle_name:
                        e.target.value,
                    })
                  }
                />
              </label>

              <label>
                Role

                <select
                  required
                  value={form.role_id}
                  onChange={(e) =>
                    setForm({
                      ...form,
                      role_id:
                        e.target.value,
                    })
                  }
                >
                  <option value="">
                    Select role...
                  </option>

                  {roles.map((role) => (
                    <option
                      key={role.id}
                      value={role.id}
                    >
                      {role.name}
                    </option>
                  ))}
                </select>
              </label>

              <div className="modal-actions">
                <button
                  type="button"
                  className="secondary-button"
                  onClick={() =>
                    setShowInvite(false)
                  }
                >
                  Cancel
                </button>

                <button
                  type="submit"
                  className="primary-action"
                  disabled={
                    busy === "invite"
                  }
                >
                  {busy === "invite"
                    ? "Sending..."
                    : "Send Invitation"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </section>
  );
}