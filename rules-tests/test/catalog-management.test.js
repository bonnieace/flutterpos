import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
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

test("an owner, administrator, or manager stocks the catalog", async () => {
  await seedBusiness();

  for (const uid of ["owner-a", "admin-a", "manager-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertSucceeds(
      setDoc(doc(firestore, `${CATEGORIES}/ct_${uid}`), category(uid)),
    );
    await assertSucceeds(
      setDoc(doc(firestore, `${PRODUCTS}/pd_${uid}`), product(uid)),
    );
  }
});

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

test("a create must carry an integer quantity", async () => {
  // The single condition `allow create` checks. Everything else about the
  // shape is the client's boundary, which is why that boundary is tested in
  // Dart against the strict read model rather than only here.
  await seedBusiness();
  const firestore = authenticatedFirestore(testEnvironment, "owner-a");

  for (const quantity of ["0", 0.5, null, true]) {
    await assertFails(
      setDoc(doc(firestore, `${PRODUCTS}/pd_bad`), product("owner-a", { quantity })),
    );
  }
  await assertSucceeds(
    setDoc(doc(firestore, `${PRODUCTS}/pd_good`), product("owner-a")),
  );
});

test("replaying a create onto an existing product is refused", async () => {
  // The client derives one deterministic document ID per confirmed create and
  // reuses it across a retry. That is only safe because a `set` onto a document
  // that already exists is an *update*, and the update rule permits nothing but
  // a strictly decreasing quantity - so a replay can never quietly rewrite a
  // product that already sold.
  await seedBusiness();
  const firestore = authenticatedFirestore(testEnvironment, "owner-a");
  const path = `${PRODUCTS}/pd_deterministic`;

  await assertSucceeds(setDoc(doc(firestore, path), product()));
  await assertFails(setDoc(doc(firestore, path), product()));
  await assertFails(
    setDoc(doc(firestore, path), product("owner-a", { price: 70 })),
  );
});

test("only an owner or administrator retires a product", async () => {
  await seedBusiness();

  for (const [uid, retires] of [
    ["cashier-a", false],
    ["manager-a", false],
    ["admin-a", true],
    ["owner-a", true],
  ]) {
    await seedDocuments(testEnvironment, {
      [`${PRODUCTS}/pd_seeded`]: {
        name: "White bread loaf",
        SKU: "6161100000019",
        price: 65,
        quantity: 40,
        categoryId: "cat-bakery",
      },
    });
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const target = doc(firestore, `${PRODUCTS}/pd_seeded`);
    if (retires) {
      await assertSucceeds(deleteDoc(target));
    } else {
      // A manager stocks the shelf and may not empty it, which is exactly the
      // split the client's two role lists model.
      await assertFails(deleteDoc(target));
    }
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
  // broken rule.
  await assertSucceeds(
    setDoc(
      doc(foreign, "tenants/tenant-b/products/pd_new"),
      product("owner-b"),
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
