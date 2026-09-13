import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";

import {
  activeTenantDocuments,
  authenticatedFirestore,
  createRulesTestEnvironment,
  seedDocuments,
} from "./support.js";

const PRODUCTS = "tenants/tenant-a/products";
const CATEGORIES = "tenants/tenant-a/categories";

let testEnvironment;

before(async () => {
  testEnvironment = await createRulesTestEnvironment();
});

afterEach(async () => {
  if (testEnvironment) await testEnvironment.clearFirestore();
});

after(async () => {
  if (testEnvironment) await testEnvironment.cleanup();
});

/**
 * Exactly the document the client writes: every field the strict read model
 * demands, its provenance, and a server timestamp. Nothing else.
 */
function product(uid = "owner-a", overrides = {}) {
  return {
    name: "White bread loaf",
    SKU: "6161100000019",
    price: 65,
    quantity: 0,
    categoryId: "cat-bakery",
    createdBy: uid,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function category(uid = "owner-a", name = "Bakery") {
  return { name, createdBy: uid, createdAt: serverTimestamp() };
}

async function seedBusiness() {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "owner-a", role: "owner" }),
    ...Object.fromEntries(
      [
        ["admin-a", "admin"],
        ["manager-a", "manager"],
        ["cashier-a", "cashier"],
      ].flatMap(([uid, role]) => [
        [
          `users/${uid}`,
          {
            accountType: "tenant_user",
            globalStatus: "active",
            membershipCount: 1,
          },
        ],
        [`tenants/tenant-a/staff/${uid}`, { uid, role, status: "active" }],
      ]),
    ),
  });
}

test("a cashier reads the catalog and never changes it", async () => {
  // The read is deliberately as wide as the set of people who may sell: a till
  // cannot price a sale without the product document.
  await seedBusiness();
  await seedDocuments(testEnvironment, {
    [`${PRODUCTS}/pd_seeded`]: {
      name: "White bread loaf",
      SKU: "6161100000019",
      price: 65,
      quantity: 40,
      categoryId: "cat-bakery",
    },
    [`${CATEGORIES}/cat-bakery`]: { name: "Bakery" },
  });
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  await assertSucceeds(getDoc(doc(firestore, `${PRODUCTS}/pd_seeded`)));
  await assertSucceeds(getDoc(doc(firestore, `${CATEGORIES}/cat-bakery`)));
  await assertFails(
    setDoc(doc(firestore, `${PRODUCTS}/pd_new`), product("cashier-a")),
  );
  await assertFails(
    setDoc(doc(firestore, `${CATEGORIES}/ct_new`), category("cashier-a")),
  );
  await assertFails(deleteDoc(doc(firestore, `${PRODUCTS}/pd_seeded`)));
});

test("no client may create a product, whatever its role", async () => {
  // **`allow create` is `if false`, and that is the whole rule.** It used to
  // admit any document owner, admin or manager cared to write while checking one
  // field of it, so the client was the only thing standing between a business
  // and a product its own till could not parse. It could not merely be tightened
  // either: a create may now carry an opening quantity, and the ledger entry
  // that accounts for those units is server-write-only, so both have to be
  // written by one principal. `createProduct` is that principal.
  await seedBusiness();

  for (const uid of ["owner-a", "admin-a", "manager-a", "cashier-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertFails(
      setDoc(doc(firestore, `${PRODUCTS}/pd_new`), product(uid)),
    );
    // Nor by opening with stock, which is the thing that made this server work.
    await assertFails(
      setDoc(
        doc(firestore, `${PRODUCTS}/pd_stocked`),
        product(uid, { quantity: 24 }),
      ),
    );
  }
});

test("a category is still a client write, and still checks nothing", async () => {
  // The other half of the pair, deliberately unchanged. A category carries no
  // quantity and has no ledger hanging off it, so nothing about it needs a
  // transaction - and `QueuedTenantCatalogWriter` still replays it as a `set`.
  // This is the backend/UI contract mismatch the inventory audit recorded
  // separately: the rule admits delete and no UI offers one.
  await seedBusiness();

  for (const [uid, writes] of [
    ["owner-a", true],
    ["admin-a", true],
    ["manager-a", true],
    ["cashier-a", false],
  ]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const assertion = writes ? assertSucceeds : assertFails;
    await assertion(
      setDoc(doc(firestore, `${CATEGORIES}/ct_${uid}`), category(uid)),
    );
  }
});

test("the checkout decrement is the only client update a product accepts", async () => {
  // Unchanged by the create rule closing, and the half that must never move: a
  // cashier's till has to be able to take stock down with no connection, and
  // nothing else about a product may be touched from a device.
  await seedBusiness();
  // Seeded explicitly: `seedBusiness` writes the roster and no catalog, and an
  // update against a document that does not exist is refused for the wrong
  // reason - which would make the `assertSucceeds` below unreachable and the
  // `assertFails` above vacuous.
  await seedDocuments(testEnvironment, {
    [`${PRODUCTS}/pd_seeded`]: {
      name: "White bread loaf",
      SKU: "6161100000019",
      price: 65,
      quantity: 40,
      categoryId: "cat-bakery",
    },
  });
  const firestore = authenticatedFirestore(testEnvironment, "owner-a");

  await assertFails(
    updateDoc(doc(firestore, `${PRODUCTS}/pd_seeded`), {
      cost: 1,
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(firestore, `${PRODUCTS}/pd_seeded`), {
      quantity: 39,
      cost: 1,
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(doc(firestore, `${PRODUCTS}/pd_seeded`), {
      quantity: 39,
      updatedAt: serverTimestamp(),
    }),
  );
});

test("a set onto an existing product cannot rewrite it", async () => {
  // What the deterministic-ID replay used to rest on, and still worth pinning:
  // the update rule permits nothing but a strictly decreasing quantity, so no
  // `set` can quietly rewrite a product that already sold. The create half of
  // this moved to `functions/src/operations/productCreate.test.ts`, where the
  // idempotency record is now what answers a replay.
  await seedBusiness();
  const firestore = authenticatedFirestore(testEnvironment, "owner-a");

  await assertFails(
    setDoc(doc(firestore, `${PRODUCTS}/pd_seeded`), product("owner-a")),
  );
  await assertFails(
    setDoc(
      doc(firestore, `${PRODUCTS}/pd_seeded`),
      product("owner-a", { price: 70 }),
    ),
  );
});

test("no client may delete a product, whatever its role", async () => {
  // **This asserted that an owner and an administrator could, until
  // 2026-09-13.** That delete was what "Retire product" did, and it removed the
  // document carrying the current quantity: nothing recorded the stock leaving,
  // every past sale line went on naming an ID nothing answered to, and the
  // `stock_movements` below it were orphaned rather than deleted - Firestore
  // keeps a subcollection when its parent goes - so the ledger survived with no
  // way into it, because the way in is the product.
  //
  // `setProductRetired` sets a flag and writes the movement clearing the stock
  // in one transaction. Who may do it is unchanged: owner and administrator, as
  // this rule said, now enforced by the callable instead.
  await seedBusiness();
  await seedDocuments(testEnvironment, {
    [`${PRODUCTS}/pd_seeded`]: {
      name: "White bread loaf",
      SKU: "6161100000019",
      price: 65,
      quantity: 40,
      categoryId: "cat-bakery",
    },
  });

  for (const uid of ["owner-a", "admin-a", "manager-a", "cashier-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertFails(deleteDoc(doc(firestore, `${PRODUCTS}/pd_seeded`)));
  }
});

test("a category is writable by everyone who may add a product", async () => {
  // Wider than `products` deliberately: `allow create, update, delete` on
  // `categories` names all three roles. The client offers only create, so this
  // records what the rule permits rather than what the app does.
  await seedBusiness();
  await seedDocuments(testEnvironment, {
    [`${CATEGORIES}/cat-bakery`]: { name: "Bakery" },
  });
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  await assertSucceeds(
    setDoc(doc(firestore, `${CATEGORIES}/cat-bakery`), category("manager-a")),
  );
  await assertSucceeds(deleteDoc(doc(firestore, `${CATEGORIES}/cat-bakery`)));
});

test("another business's catalog is never reached", async () => {
  await seedBusiness();
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "owner-b",
      tenantId: "tenant-b",
      role: "owner",
    }),
    [`${PRODUCTS}/pd_seeded`]: {
      name: "White bread loaf",
      SKU: "6161100000019",
      price: 65,
      quantity: 40,
      categoryId: "cat-bakery",
    },
  });

  const foreign = authenticatedFirestore(testEnvironment, "owner-b");
  await assertFails(getDoc(doc(foreign, `${PRODUCTS}/pd_seeded`)));
  await assertFails(
    setDoc(doc(foreign, `${PRODUCTS}/pd_new`), product("owner-b")),
  );
  await assertFails(deleteDoc(doc(foreign, `${PRODUCTS}/pd_seeded`)));
  // Its own business still answers, so the denial is the boundary and not a
  // broken rule. A category rather than a product, because no client creates a
  // product anywhere any more - which would make this control pass for the same
  // reason the denials above do, and prove nothing.
  await assertSucceeds(
    setDoc(
      doc(foreign, "tenants/tenant-b/categories/ct_new"),
      category("owner-b"),
    ),
  );
});

test("a deactivated or globally disabled member stocks nothing", async () => {
  await seedBusiness();
  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/staff/manager-a": {
      uid: "manager-a",
      role: "manager",
      status: "inactive",
    },
    "users/admin-a": {
      accountType: "tenant_user",
      globalStatus: "disabled",
      membershipCount: 1,
    },
  });

  for (const uid of ["manager-a", "admin-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertFails(
      setDoc(doc(firestore, `${PRODUCTS}/pd_${uid}`), product(uid)),
    );
    await assertFails(
      setDoc(doc(firestore, `${CATEGORIES}/ct_${uid}`), category(uid)),
    );
  }
});

test("a suspended or archived business stocks nothing", async () => {
  // A lifecycle state the platform set is not something a tenant works around
  // by editing its own catalog.
  for (const status of ["suspended", "archived", "pending", "rejected"]) {
    await seedBusiness();
    await seedDocuments(testEnvironment, {
      "tenants/tenant-a": {
        name: "tenant-a",
        ownerUid: "owner-a",
        status,
      },
      [`${PRODUCTS}/pd_seeded`]: {
        name: "White bread loaf",
        SKU: "6161100000019",
        price: 65,
        quantity: 40,
        categoryId: "cat-bakery",
      },
    });
    const firestore = authenticatedFirestore(testEnvironment, "owner-a");
    await assertFails(
      setDoc(doc(firestore, `${PRODUCTS}/pd_new`), product()),
    );
    await assertFails(deleteDoc(doc(firestore, `${PRODUCTS}/pd_seeded`)));
    await testEnvironment.clearFirestore();
  }
});

test("an unauthenticated client reads and writes nothing", async () => {
  await seedBusiness();
  const firestore = testEnvironment.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(firestore, `${PRODUCTS}/pd_seeded`)));
  await assertFails(setDoc(doc(firestore, `${PRODUCTS}/pd_new`), product()));
  await assertFails(deleteDoc(doc(firestore, `${PRODUCTS}/pd_seeded`)));
});
