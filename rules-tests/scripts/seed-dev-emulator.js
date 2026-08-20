/**
 * Seeds the local Firebase emulator suite with the smallest business that can
 * actually ring up a sale, so a developer can drive the real app end to end.
 *
 * This script is destructive by nature and a mis-pointed run is unrecoverable,
 * so it refuses to start unless the Admin SDK is already pinned at emulators.
 * `FIRESTORE_EMULATOR_HOST` and `FIREBASE_AUTH_EMULATOR_HOST` are not a hint
 * to this script - they are what makes `firebase-admin` itself incapable of
 * reaching a real project - so requiring them is the guarantee, not a check.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

/** The project the Flutter app is built against; see `lib/firebase_options.dart`. */
const DEFAULT_PROJECT_ID = "multitenant-pos-b8326";

const TENANT_ID = "dev-shop";
const TENANT_NAME = "Dev Corner Shop";
const TENANT_SLUG = "dev-corner-shop";
const OWNER_EMAIL = "owner@example.com";
const OWNER_PASSWORD = "Local-emulator-password-123!";
const OWNER_NAME = "Dev Owner";
const CURRENCY = "KES";

const CATEGORIES = [
  { id: "cat-bakery", name: "Bakery" },
  { id: "cat-drinks", name: "Drinks" },
  { id: "cat-household", name: "Household" },
];

/**
 * Two products deliberately share the SKU `5901234123457`. Nothing in the
 * Rules or the catalog cache makes a SKU unique, and the till refuses a scan
 * that matches more than one product, so the collision has to be reachable
 * locally or that refusal can never be seen.
 */
const PRODUCTS = [
  {
    id: "prod-bread",
    name: "White bread loaf",
    SKU: "6161100000019",
    price: 65,
    quantity: 40,
    categoryId: "cat-bakery",
  },
  {
    id: "prod-mandazi",
    name: "Mandazi",
    SKU: "6161100000026",
    price: 20,
    quantity: 120,
    categoryId: "cat-bakery",
  },
  {
    id: "prod-soda-300",
    name: "Soda 300ml",
    SKU: "6161100000033",
    price: 50,
    quantity: 96,
    categoryId: "cat-drinks",
  },
  {
    id: "prod-water-1l",
    name: "Water 1L",
    SKU: "6161100000040",
    price: 80,
    quantity: 0,
    categoryId: "cat-drinks",
  },
  {
    id: "prod-milk-500",
    name: "Milk 500ml",
    SKU: "6161100000057",
    price: 70,
    quantity: -3,
    categoryId: "cat-drinks",
  },
  {
    id: "prod-soap-blue",
    name: "Bar soap - blue",
    SKU: "5901234123457",
    price: 145,
    quantity: 24,
    categoryId: "cat-household",
  },
  {
    id: "prod-soap-green",
    name: "Bar soap - green",
    SKU: "5901234123457",
    price: 145,
    quantity: 18,
    categoryId: "cat-household",
  },
  {
    id: "prod-uncategorised",
    name: "Charcoal 2kg",
    SKU: "6161100000071",
    price: 260,
    quantity: 12,
    categoryId: "cat-not-cached",
  },
];

function requireEmulator(variable) {
  const value = process.env[variable];
  if (!value) {
    throw new Error(
      `${variable} is not set. Seeding refuses to run outside the emulators; ` +
        "start them with `npm --prefix rules-tests run emulators:dev`.",
    );
  }
  return value;
}

function assertNoRealCredentials() {
  // The emulator host variables above already make production unreachable.
  // This is a second, cheaper signal that the shell was set up for a real
  // project, which is worth refusing on rather than explaining afterwards.
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    throw new Error(
      "GOOGLE_APPLICATION_CREDENTIALS is set. Unset it before seeding: real " +
        "service-account credentials have no business in a local seed run.",
    );
  }
}

async function ensureOwner(auth) {
  const record = await auth
    .getUserByEmail(OWNER_EMAIL)
    .catch((error) => {
      if (error.code === "auth/user-not-found") return undefined;
      throw error;
    });
  if (record) {
    // The account is stuck behind the verification gate in
    // `lib/tenancy/tenant_request.dart` unless the address is verified, and a
    // re-run must repair an account that was created without it.
    await auth.updateUser(record.uid, {
      password: OWNER_PASSWORD,
      emailVerified: true,
      displayName: OWNER_NAME,
      disabled: false,
    });
    return record.uid;
  }
  const created = await auth.createUser({
    email: OWNER_EMAIL,
    password: OWNER_PASSWORD,
    emailVerified: true,
    displayName: OWNER_NAME,
  });
  return created.uid;
}

async function seedFirestore(firestore, uid) {
  const now = Timestamp.now();
  const tenant = firestore.collection("tenants").doc(TENANT_ID);

  // Written first, deliberately. `CheckoutCatalogCacheRefresher` refuses with
  // `configurationUnavailable` when this document is missing, and then no sale
  // can be rung up at all however complete the catalog is.
  await tenant.collection("configuration").doc("checkout").set({
    currency: CURRENCY,
    updatedAt: now,
  });

  // The shop's own name, which is what a receipt prints at the top and what the
  // home titles itself with. Without it `TenantBrandingRepository.load` returns
  // null, the home falls back to the membership's tenant name, and the receipt
  // falls back to `ReceiptWords.unnamedBusiness` - "Sales receipt". That is
  // correct behaviour and it looks like a bug on paper, which is why a business
  // that can ring up a sale should also be able to name itself.
  await tenant.collection("configuration").doc("branding").set({
    companyName: TENANT_NAME,
    slogan: "Everything the corner needs",
    updatedAt: now,
  });

  await tenant.set({
    name: TENANT_NAME,
    slug: TENANT_SLUG,
    status: "active",
    ownerUid: uid,
    createdAt: now,
    updatedAt: now,
  });

  await tenant.collection("staff").doc(uid).set({
    uid,
    email: OWNER_EMAIL,
    name: OWNER_NAME,
    role: "owner",
    status: "active",
    invitationStatus: "accepted",
    joinedAt: now,
    updatedAt: now,
  });

  const user = firestore.collection("users").doc(uid);
  await user.set({
    email: OWNER_EMAIL,
    displayName: OWNER_NAME,
    accountType: "tenant_user",
    identityOrigin: "self_signup",
    globalStatus: "active",
    defaultTenantId: TENANT_ID,
    membershipCount: 1,
    ownedTenantCount: 1,
    ownedActiveTenantCount: 1,
    createdAt: now,
    updatedAt: now,
  });

  // `listMyTenants` pages this mirror collection and overlays the canonical
  // documents above onto it, so without this entry the app signs in and finds
  // no business at all.
  await user.collection("tenant_memberships").doc(TENANT_ID).set({
    tenantId: TENANT_ID,
    tenantName: TENANT_NAME,
    tenantSlug: TENANT_SLUG,
    role: "owner",
    membershipStatus: "active",
    tenantStatus: "active",
    invitationStatus: "accepted",
    isOwner: true,
    mirrorVersion: 1,
    createdAt: now,
    joinedAt: now,
    updatedAt: now,
  });

  const batch = firestore.batch();
  for (const category of CATEGORIES) {
    batch.set(tenant.collection("categories").doc(category.id), {
      name: category.name,
      createdAt: now,
      updatedAt: now,
    });
  }
  for (const product of PRODUCTS) {
    const { id, ...fields } = product;
    batch.set(tenant.collection("products").doc(id), {
      ...fields,
      createdAt: now,
      updatedAt: now,
    });
  }
  await batch.commit();
  return { uid, tenantId: TENANT_ID };
}

async function verifySeed(firestore, uid) {
  // A seed nobody checked is a seed that silently half-applied. These are the
  // three documents whose absence produces a confusing app rather than an
  // obvious one: no configuration means no till, no staff record means no
  // access, no mirror means no business in the list.
  const tenant = firestore.collection("tenants").doc(TENANT_ID);
  const required = [
    ["configuration/checkout", tenant.collection("configuration").doc("checkout")],
    [`staff/${uid}`, tenant.collection("staff").doc(uid)],
    [
      `users/${uid}/tenant_memberships/${TENANT_ID}`,
      firestore
        .collection("users")
        .doc(uid)
        .collection("tenant_memberships")
        .doc(TENANT_ID),
    ],
  ];
  for (const [label, reference] of required) {
    const snapshot = await reference.get();
    if (!snapshot.exists) throw new Error(`Seeding did not write ${label}.`);
  }
  const products = await tenant.collection("products").get();
  if (products.size !== PRODUCTS.length) {
    throw new Error(
      `Seeding wrote ${products.size} products, expected ${PRODUCTS.length}.`,
    );
  }
}

/** Reports the ports the app must be pointed at, read from `firebase.json`. */
function declaredEmulatorPorts() {
  const config = JSON.parse(
    readFileSync(
      fileURLToPath(new URL("../../firebase.json", import.meta.url)),
      "utf8",
    ),
  );
  const emulators = config.emulators;
  if (!emulators) {
    throw new Error("firebase.json declares no emulators block.");
  }
  return emulators;
}

export async function seedDevEmulator() {
  requireEmulator("FIRESTORE_EMULATOR_HOST");
  requireEmulator("FIREBASE_AUTH_EMULATOR_HOST");
  assertNoRealCredentials();
  const projectId = process.env.SEED_PROJECT_ID ?? DEFAULT_PROJECT_ID;
  const ports = declaredEmulatorPorts();

  const app = initializeApp({ projectId }, `seed-${Date.now()}`);
  try {
    const uid = await ensureOwner(getAuth(app));
    const firestore = getFirestore(app);
    const result = await seedFirestore(firestore, uid);
    await verifySeed(firestore, uid);
    console.log(
      [
        "Seeded the local emulators.",
        `  project     ${projectId}`,
        `  business    ${TENANT_NAME} (${result.tenantId})`,
        `  sign in as  ${OWNER_EMAIL} / ${OWNER_PASSWORD}`,
        `  auth        ${process.env.FIREBASE_AUTH_EMULATOR_HOST}`,
        `  firestore   ${process.env.FIRESTORE_EMULATOR_HOST}`,
        `  functions   port ${ports.functions?.port ?? "unset"}`,
        "",
        "Run the app against it with:",
        "  flutter run --dart-define=USE_FIREBASE_EMULATORS=true",
        "",
      ].join("\n"),
    );
    return result;
  } finally {
    await deleteApp(app);
  }
}

/** Blocks until interrupted, so `emulators:exec` keeps the suite alive. */
function hold() {
  console.log("Emulators are up. Press Ctrl+C to stop them.\n");
  return new Promise((resolve) => {
    process.on("SIGINT", resolve);
    process.on("SIGTERM", resolve);
    // An interval with no other work keeps the event loop alive without
    // spinning; `emulators:exec` terminates this process on shutdown anyway.
    setInterval(() => {}, 1 << 30);
  });
}

const invokedDirectly =
  process.argv[1] !== undefined &&
  import.meta.url === pathToFileURL(process.argv[1]).href;

if (invokedDirectly) {
  try {
    await seedDevEmulator();
    if (process.argv.includes("--hold")) await hold();
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  }
}
