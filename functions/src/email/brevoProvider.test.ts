import assert from "node:assert/strict";
import test from "node:test";
import {BrevoEmailProvider} from "./brevoProvider";
import {EmailProviderError} from "./contracts";

const CONFIG = {
  apiKey: "test-api-key-at-least-sixteen-bytes",
  senderAddress: "no-reply@example.com",
  senderName: "ChillTent",
};
const MESSAGE = {
  deliveryId: "delivery-1",
  recipient: "person@example.com",
  template: "password_reset" as const,
  actionUrl: "https://auth.example.test/reset?oobCode=a%26b",
};

test("Brevo adapter sends a source-controlled reset template without tracking", async () => {
  let captured: RequestInit | undefined;
  const provider = new BrevoEmailProvider(CONFIG, async (_input, init) => {
    captured = init;
    return new Response(JSON.stringify({messageId: "provider-message-1"}), {
      status: 201,
      headers: {"content-type": "application/json"},
    });
  });

  assert.deepEqual(await provider.send(MESSAGE), {
    provider: "brevo",
    providerMessageId: "provider-message-1",
  });
  const body = JSON.parse(String(captured?.body)) as Record<string, unknown>;
  assert.deepEqual(body.tags, ["password-reset"]);
  assert.equal("params" in body, false);
  assert.equal("trackClicks" in body, false);
  assert.deepEqual(body.headers, {
    "Idempotency-Key": "delivery-1",
    "X-Mailin-Track-Clicks": "0",
    "X-Mailin-Track-Opens": "0",
  });
  assert.match(String(body.htmlContent), /a%26b/);
});

test("Brevo adapter classifies retryable HTTP errors without retaining bodies", async () => {
  const provider = new BrevoEmailProvider(CONFIG, async () =>
    new Response("recipient@example.com secret provider text", {status: 429}));

  await assert.rejects(provider.send(MESSAGE), (error: unknown) => {
    assert.ok(error instanceof EmailProviderError);
    assert.equal(error.safeCode, "provider_http_429");
    assert.equal(error.retryable, true);
    assert.equal(error.message.includes("recipient@example.com"), false);
    return true;
  });
});
