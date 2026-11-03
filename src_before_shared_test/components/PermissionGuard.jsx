import { useUserContext } from "../contexts/UserContext";

export default function PermissionGuard({ permission, any = [], fallback = null, children }) {
  const { hasPermission, loading } = useUserContext();
  if (loading) return fallback;

  const allowed =
    (!permission && !any.length) ||
    (permission && hasPermission(permission)) ||
    (any.length && any.some(hasPermission));

  return allowed ? children : fallback;
}
