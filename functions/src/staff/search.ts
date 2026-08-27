/** Shared normalization for canonical staff directory search projections. */
export function normalizeStaffSearchText(value: string): string {
  return value.trim().toLowerCase().replace(/\s+/g, " ");
}

/**
 * Stable name/email prefixes used by the dedicated staff directory query.
 *
 * The full normalized values support ordinary left-to-right typing, while the
 * word/segment values let somebody find "Jane Njeri" with "njeri" and an
 * address with either its local or domain segment. One-character searches are
 * intentionally absent to keep the index and result set bounded.
 */
export function staffSearchFields(
  name: string,
  email: string
): {searchName: string; searchPrefixes: string[]} {
  const normalizedName = normalizeStaffSearchText(name);
  const normalizedEmail = normalizeStaffSearchText(email);
  const tokens = new Set<string>([
    normalizedName,
    ...normalizedName.split(" "),
    normalizedEmail,
    ...normalizedEmail.split(/[.@_+\-]/),
  ]);
  const prefixes = new Set<string>();
  for (const token of tokens) {
    const maximum = Math.min(token.length, 120);
    for (let length = 2; length <= maximum; length += 1) {
      prefixes.add(token.slice(0, length));
    }
  }
  return {
    searchName: normalizedName || normalizedEmail,
    searchPrefixes: [...prefixes].sort(),
  };
}
