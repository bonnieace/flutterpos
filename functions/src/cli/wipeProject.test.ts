import assert from "node:assert/strict";
import test from "node:test";
import {optionsOf, SURFACES} from "./wipeProject";

test("the project wipe is a dry run until --apply, and needs a project", () => {
  const options = optionsOf(["--project", "multitenant-pos-b8326"]);
  assert.equal(options.apply, false);
  assert.equal(options.projectId, "multitenant-pos-b8326");
  assert.equal(options.location, "us-central1");
  assert.equal(options.skip.size, 0);

  assert.throws(() => optionsOf([]), /--project/);
  assert.throws(() => optionsOf(["--project", "Bad_Project"]), /--project/);
  assert.throws(() => optionsOf(["--project", "no"]), /--project/);
});

test("--apply is refused unless --confirm repeats the project exactly", () => {
  // The whole guard: a recalled command line with the wrong --project must not
  // delete anything, and --confirm is the second place the ID has to agree.
  assert.throws(
    () => optionsOf(["--apply", "--project", "tenant-sit"]),
    /--confirm/
  );
  assert.throws(
    () => optionsOf([
      "--apply", "--project", "tenant-sit", "--confirm", "tenant-prod",
    ]),
    /--confirm/
  );
  assert.throws(
    () => optionsOf([
      "--apply", "--project", "tenant-sit", "--confirm", "tenant-sit ",
    ]),
    /--confirm/
  );

  const options = optionsOf([
    "--apply", "--project", "tenant-sit", "--confirm", "tenant-sit",
  ]);
  assert.equal(options.apply, true);
});

test("each surface can be skipped, and skipping every one is refused", () => {
  for (const surface of SURFACES) {
    const options = optionsOf(["--project", "tenant-sit", `--skip-${surface}`]);
    assert.deepEqual([...options.skip], [surface]);
  }
  const skipped = optionsOf([
    "--project", "tenant-sit", "--skip-auth", "--skip-storage",
  ]);
  assert.equal(skipped.skip.has("auth"), true);
  assert.equal(skipped.skip.has("storage"), true);
  assert.equal(skipped.skip.has("firestore"), false);

  assert.throws(
    () => optionsOf([
      "--project", "tenant-sit",
      ...SURFACES.map((surface) => `--skip-${surface}`),
    ]),
    /nothing to do/
  );
});

test("the Cloud Tasks location is validated rather than interpolated raw", () => {
  assert.equal(
    optionsOf(["--project", "tenant-sit", "--location", "europe-west1"]).location,
    "europe-west1"
  );
  assert.throws(
    () => optionsOf(["--project", "tenant-sit", "--location", "../../queues"]),
    /--location/
  );
});
