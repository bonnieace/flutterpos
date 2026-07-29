import assert from "node:assert/strict";
import test from "node:test";
import {
  allRecipientHashes,
  hashRecipient,
  normalizeEmail,
  parseRecipientHmacKeyring,
  recipientHashMatches,
} from "./recipientHash";

const KEYRING_JSON = JSON.stringify({
  currentVersion: "v2",
  keys: {
    v2: "current-test-recipient-key-that-has-at-least-thirty-two-bytes",
    v1: "previous-test-recipient-key-that-has-at-least-thirty-two-bytes",
  },
});

test("recipient HMAC keyring supports current and previous lookup versions", () => {
  const keyring = parseRecipientHmacKeyring(KEYRING_JSON);
  const hashes = allRecipientHashes("person@example.com", keyring);
  assert.deepEqual(hashes.map((hash) => hash.keyVersion), ["v2", "v1"]);
  assert.notEqual(hashes[0].recipientHash, hashes[1].recipientHash);
  assert.equal(hashes[0].recipientHash.includes("person@example.com"), false);
  assert.equal(hashes[0].documentId.length, 64);
  assert.equal(recipientHashMatches(
    "person@example.com",
    hashes[1].recipientHash,
    "v1",
    keyring
  ), true);
});

test("recipient matching is bound to normalized email and key version", () => {
  const keyring = parseRecipientHmacKeyring(KEYRING_JSON);
  const hash = hashRecipient("person@example.com", keyring);
  assert.equal(normalizeEmail(" Person@Example.com "), "person@example.com");
  assert.equal(recipientHashMatches(
    "other@example.com",
    hash.recipientHash,
    hash.keyVersion,
    keyring
  ), false);
  assert.equal(recipientHashMatches(
    "person@example.com",
    hash.recipientHash,
    "retired",
    keyring
  ), false);
});

test("malformed or weak keyrings fail closed", () => {
  assert.throws(() => parseRecipientHmacKeyring("not-json"));
  assert.throws(() => parseRecipientHmacKeyring(JSON.stringify({
    currentVersion: "v1",
    keys: {v1: "short"},
  })));
  assert.throws(() => parseRecipientHmacKeyring(JSON.stringify({
    currentVersion: "v2",
    keys: {v1: "a-secure-previous-key-that-is-more-than-thirty-two-bytes"},
  })));
});
