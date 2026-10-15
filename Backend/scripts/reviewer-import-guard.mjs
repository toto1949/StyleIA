/**
 * Allow a protected production data import into an otherwise empty SceneMe
 * database containing only the pre-provisioned Apple App Review account.
 * Never merge arbitrary populated databases or silently overwrite a user.
 */
export function reviewerImportCarryover(current, incoming, email = "") {
  const populatedKeys = [
    "users", "uploads", "jobs", "usage", "creditAccounts", "creditGrants",
    "creditLedger", "entitlements", "sessions", "appStoreTransactions",
    "appStoreNotifications"
  ];
  const existingUsers = current.users || [];
  const isEmpty = populatedKeys.every((key) => !Array.isArray(current[key]) || current[key].length === 0);
  if (isEmpty) return null;

  const normalizedEmail = String(email || "").trim().toLowerCase();
  const onlyReviewer = normalizedEmail
    && existingUsers.length === 1
    && existingUsers[0].email === normalizedEmail
    && existingUsers[0].passwordHash
    && existingUsers[0].passwordSalt
    && populatedKeys.filter((key) => key !== "users")
      .every((key) => !Array.isArray(current[key]) || current[key].length === 0);
  if (!onlyReviewer) {
    throw new Error("Refusing to import into a non-empty SceneMe database.");
  }

  if ((incoming.users || []).some((user) =>
    user.id === existingUsers[0].id || String(user.email || "").toLowerCase() === normalizedEmail
  )) {
    throw new Error("Legacy import conflicts with the Apple App Review account; resolve manually.");
  }
  return { ...existingUsers[0] };
}
