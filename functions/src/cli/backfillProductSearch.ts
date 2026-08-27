import {getApps, initializeApp} from "firebase-admin/app";
import {
  DocumentData,
  FieldPath,
  Query,
  QueryDocumentSnapshot,
  getFirestore,
} from "firebase-admin/firestore";
import {productSearchFields} from "../operations/productUpdate";

export interface Options {
  apply: boolean;
  tenantId?: string;
  pageSize: number;
}

export function optionsOf(args: string[]): Options {
  const apply = args.includes("--apply");
  const tenantAt = args.indexOf("--tenant");
  const pageAt = args.indexOf("--page-size");
  const tenantId = tenantAt < 0 ? undefined : args[tenantAt + 1];
  const pageSize = pageAt < 0 ? 200 : Number(args[pageAt + 1]);
  if (tenantAt >= 0 && (!tenantId || tenantId.includes("/"))) {
    throw new Error("--tenant requires one Firestore document ID.");
  }
  if (!Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > 400) {
    throw new Error("--page-size must be an integer from 1 to 400.");
  }
  return {apply, tenantId, pageSize};
}

function sameStrings(left: unknown, right: readonly string[]): boolean {
  return Array.isArray(left) &&
    left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

export function productSearchUpdateOf(data: DocumentData): ReturnType<
  typeof productSearchFields
> | null {
  if (typeof data.name !== "string" || typeof data.SKU !== "string") {
    throw new Error("Product name and SKU must be strings.");
  }
  const search = productSearchFields(data.name, data.SKU);
  return data.searchName === search.searchName &&
    sameStrings(data.searchPrefixes, search.searchPrefixes) ? null : search;
}

export async function run(): Promise<void> {
  const options = optionsOf(process.argv.slice(2));
  if (getApps().length === 0) initializeApp();
  const db = getFirestore();
  let query: Query<DocumentData> = options.tenantId ?
    db.collection("tenants").doc(options.tenantId).collection("products") :
    db.collectionGroup("products");
  query = query.orderBy(FieldPath.documentId()).limit(options.pageSize);

  let cursor: QueryDocumentSnapshot<DocumentData> | undefined;
  let scanned = 0;
  let changed = 0;
  let invalid = 0;
  do {
    const page = await (cursor ? query.startAfter(cursor) : query).get();
    if (page.empty) break;
    const batch = db.batch();
    let writes = 0;
    for (const document of page.docs) {
      scanned += 1;
      const data = document.data();
      let search: ReturnType<typeof productSearchFields> | null;
      try {
        search = productSearchUpdateOf(data);
      } catch {
        invalid += 1;
        process.stderr.write(`Skipped unreadable product ${document.ref.path}\n`);
        continue;
      }
      if (search === null) continue;
      changed += 1;
      if (options.apply) {
        batch.update(document.ref, search);
        writes += 1;
      }
    }
    if (writes > 0) await batch.commit();
    cursor = page.docs[page.docs.length - 1];
    if (page.size < options.pageSize) break;
  } while (cursor !== undefined);

  process.stdout.write(JSON.stringify({
    mode: options.apply ? "apply" : "dry-run",
    tenantId: options.tenantId ?? null,
    scanned,
    changed,
    invalid,
  }) + "\n");
}

if (require.main === module) {
  run().catch((error: unknown) => {
    process.stderr.write(`${error instanceof Error ? error.message : error}\n`);
    process.exitCode = 1;
  });
}
