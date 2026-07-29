import assert from "node:assert/strict";
import test from "node:test";
import {bindRecipientPrivacy} from "./suppressionLookup";
import {parseRecipientHmacKeyring} from "./recipientHash";

test("shared delivery binding exposes only versioned HMAC fields for persistence", () => {
  const keyring = parseRecipientHmacKeyring(JSON.stringify({
    currentVersion: "v2",
    keys: {
      v2: "shared-current-recipient-key-longer-than-thirty-two-bytes",
      v1: "shared-previous-recipient-key-longer-than-thirty-two-bytes",
    },
  }));
  const binding = bindRecipientPrivacy(" Staff@Example.com ", keyring);
  assert.ok(binding);
  assert.equal(binding.normalizedEmail, "staff@example.com");
  assert.equal(binding.current.keyVersion, "v2");
  assert.deepEqual(binding.supported.map((hash) => hash.keyVersion), ["v2", "v1"]);
  assert.equal(binding.current.recipientHash.includes("staff@example.com"), false);
  assert.equal(binding.current.documentId.length, 64);
});
