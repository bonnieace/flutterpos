/**
 * Points the shared WhatsApp number's webhook at UzaPay, shows where it points,
 * or takes the override off.
 *
 * **Run by the developer, by hand, never by a deploy.** Setting the override
 * moves this number's message events - delivery statuses, replies, STOP -
 * from carerota's callback to UzaPay's, which is the developer's decision of
 * 2026-10-01 and theirs to time. It changes nothing in carerota and nothing
 * on the Meta app: the app's own callback stays where it is, and `clear`
 * sends the number's events back to it.
 *
 * It takes everything from the environment, so no token is typed onto a
 * command line that shell history keeps:
 *
 *   WHATSAPP_ACCESS_TOKEN       the system-user token (carerota's)
 *   WHATSAPP_PHONE_NUMBER_ID    the shared number's ID
 *   WHATSAPP_GRAPH_VERSION      optional, defaults to v23.0
 *   WHATSAPP_WEBHOOK_URL        for set: the deployed receiveWhatsappWebhook URL
 *   WHATSAPP_WEBHOOK_VERIFY_TOKEN  for set: the value deployed as that secret
 */

export const WHATSAPP_WEBHOOK_OVERRIDE_USAGE = `
npm run whatsapp-webhook -- show
npm run whatsapp-webhook -- set
npm run whatsapp-webhook -- clear

Reads WHATSAPP_ACCESS_TOKEN and WHATSAPP_PHONE_NUMBER_ID from the environment,
and for "set" WHATSAPP_WEBHOOK_URL and WHATSAPP_WEBHOOK_VERIFY_TOKEN. Meta calls
the URL with the verify token before accepting it, so deploy
receiveWhatsappWebhook with the same token first.
`.trim();

type Fetch = typeof fetch;

export interface OverrideEnvironment {
  accessToken: string;
  phoneNumberId: string;
  graphVersion: string;
  webhookUrl?: string;
  verifyToken?: string;
}

export function readOverrideEnvironment(
  env: Record<string, string | undefined>
): OverrideEnvironment {
  const accessToken = env.WHATSAPP_ACCESS_TOKEN?.trim();
  const phoneNumberId = env.WHATSAPP_PHONE_NUMBER_ID?.trim();
  if (!accessToken || !phoneNumberId) {
    throw new Error("WHATSAPP_ACCESS_TOKEN and WHATSAPP_PHONE_NUMBER_ID are required.");
  }
  return {
    accessToken,
    phoneNumberId,
    graphVersion: env.WHATSAPP_GRAPH_VERSION?.trim() || "v23.0",
    webhookUrl: env.WHATSAPP_WEBHOOK_URL?.trim(),
    verifyToken: env.WHATSAPP_WEBHOOK_VERIFY_TOKEN?.trim(),
  };
}

/** The request one command makes, so a test can read it without a network. */
export function overrideRequest(
  command: "show" | "set" | "clear",
  environment: OverrideEnvironment
): {url: string; method: "GET" | "POST"; body?: Record<string, unknown>} {
  const base = `https://graph.facebook.com/${environment.graphVersion}/` +
    environment.phoneNumberId;
  switch (command) {
  case "show":
    return {url: `${base}?fields=webhook_configuration`, method: "GET"};
  case "clear":
    return {
      url: base,
      method: "POST",
      body: {webhook_configuration: {override_callback_uri: ""}},
    };
  case "set": {
    const url = environment.webhookUrl;
    if (!url || !url.startsWith("https://") || url.length > 200) {
      throw new Error(
        "WHATSAPP_WEBHOOK_URL must be the HTTPS URL of receiveWhatsappWebhook, " +
        "at most 200 characters."
      );
    }
    if (!environment.verifyToken) {
      throw new Error("WHATSAPP_WEBHOOK_VERIFY_TOKEN is required to set the override.");
    }
    return {
      url: base,
      method: "POST",
      body: {
        webhook_configuration: {
          override_callback_uri: url,
          verify_token: environment.verifyToken,
        },
      },
    };
  }
  }
}

export async function runWhatsappWebhookOverride(
  argv: readonly string[],
  env: Record<string, string | undefined>,
  fetchImpl: Fetch = fetch
): Promise<string> {
  const command = argv[0];
  if (command !== "show" && command !== "set" && command !== "clear") {
    throw new Error(WHATSAPP_WEBHOOK_OVERRIDE_USAGE);
  }
  const environment = readOverrideEnvironment(env);
  const request = overrideRequest(command, environment);
  const response = await fetchImpl(request.url, {
    method: request.method,
    headers: {
      "authorization": `Bearer ${environment.accessToken}`,
      ...(request.body ? {"content-type": "application/json"} : {}),
    },
    body: request.body ? JSON.stringify(request.body) : undefined,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`Meta refused ${command}: ${JSON.stringify(payload)}`);
  }
  return JSON.stringify(payload, null, 2);
}

if (require.main === module) {
  runWhatsappWebhookOverride(process.argv.slice(2), process.env)
    .then((output) => {
      process.stdout.write(`${output}\n`);
    })
    .catch((error: unknown) => {
      process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
      process.exitCode = 1;
    });
}
