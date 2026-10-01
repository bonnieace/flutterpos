# WhatsApp receipts: setup and operation

How UzaPay sends receipts on WhatsApp, what has to be done in Meta and Firebase to turn it on,
and the rules the code enforces. Written 2026-10-01 alongside the feature.

## What is sent

One message per receipt, from **one shared number**, naming the shop that made the sale. Each
business chooses on its **WhatsApp** home tile:

- **Format:** the receipt as a PDF laid out like the printed one, or the totals in the message.
- **When:** automatically, to customers who agreed, once their sale reaches the server; or only
  when a cashier presses *Send on WhatsApp* (after a sale, or from the Sales report).

A cashier can always send one by hand while receipts are on, including to a walk-in's typed
number.

## The number: carerota's, reused

UzaPay reuses carerota's (Haki's) Meta setup: the same verified Meta Business, WhatsApp Business
account, phone number and phone number ID, Meta app (whose App Secret signs webhooks) and
system-user token. **Carerota's code is not changed.** UzaPay is the authority for the number and
takes its webhooks through a per-number override (below). Carerota will move to another Meta
account later.

Consequences of sharing the number:

- **Display name.** Customers see the number's existing display name; the message text names the
  shop.
- **Quality rating.** Blocks and reports of receipts lower the number's rating for carerota's
  messages too.
- **Until carerota moves:** once the override is set, carerota still sends, but its deliveries
  stop at "sent" (its statuses come to UzaPay, which drops message IDs it did not send), and carers'
  replies get UzaPay's automatic reply. That reply is worded to make sense to both: *"This number
  sends automated messages and can't read replies. Please contact the business directly."*

## Turning it on

### 1. Submit the templates

In WhatsApp Manager, on the shared account, category **Utility**, language **English (`en`)**:

| Name | Header | Body |
| --- | --- | --- |
| `uzapay_receipt_pdf_v1` | Document | Thank you for shopping at {{1}}. Your receipt {{2}} for {{3}} is attached. Reply STOP to stop receipts. |
| `uzapay_receipt_summary_v1` | none | Thank you for shopping at {{1}}. Receipt {{2}} on {{3}}: {{4}}, total {{5}}. Reply STOP to stop receipts. |

Sample values for review: `{{1}}` Mama Njeri Shop, `{{2}}` JOHN-CT-7F2-001, `{{3}}` KES 1,250.00 (PDF)
or 1 Oct 2026 (summary), `{{4}}` 3 items, `{{5}}` KES 1,250.00.

Template names cannot be edited once submitted. If Meta rejects a wording, resubmit under `_v2` and
change `functions/src/whatsapp/templates.ts` in the same commit.

### 2. Set the secrets and parameters on the project

From `functions/`, for `multitenant-pos-b8326`:

```
firebase functions:secrets:set WHATSAPP_ACCESS_TOKEN          # carerota's system-user token
firebase functions:secrets:set WHATSAPP_APP_SECRET            # the Meta app's App Secret
firebase functions:secrets:set WHATSAPP_WEBHOOK_VERIFY_TOKEN  # a new random value, UzaPay's own
```

and in `functions/.env.multitenant-pos-b8326` (parameters, not secrets):

```
WHATSAPP_PHONE_NUMBER_ID=<the shared number's ID>
WHATSAPP_GRAPH_VERSION=v23.0
WHATSAPP_TEMPLATE_LANGUAGE=en
```

**Check `WHATSAPP_GRAPH_VERSION` before deploying.** Meta retires a Graph version about two years
after release; carerota uses `v21.0`, which dates from late 2024.

With `WHATSAPP_PHONE_NUMBER_ID` empty the channel does nothing: every delivery is recorded as
*Not sent - WhatsApp receipts are not available yet*, and the WhatsApp tile says so.

**The three secrets must exist before the first deploy, even unused.** The functions that send
declare them, and a deploy refuses to go ahead while a declared secret is missing from Secret
Manager - which would hold up the customers callables too. To deploy before Meta is ready, set each
secret to a placeholder and leave `WHATSAPP_PHONE_NUMBER_ID` empty: nothing is sent.

### 3. Deploy

Rules, indexes and functions. The new functions are `createCustomer`, `updateCustomer`,
`onCustomerSale`, `processCustomerSale`, `deliverWhatsappReceipt`, `sendWhatsappReceipt`,
`getWhatsappReceiptStatus` and `receiveWhatsappWebhook`. Task queues are created on first deploy.

One index to watch: `sales (customerId ASC, __name__ DESC)`, for a customer's purchase history. The
emulator does not enforce indexes, so whether the deploy accepts that shape is confirmed on SIT.

### 4. Point the number's webhook at UzaPay (by hand, when you choose)

This moves the shared number's message events from carerota's callback to UzaPay. It is never part
of a deploy.

```
cd functions
export WHATSAPP_ACCESS_TOKEN=...            # carerota's token
export WHATSAPP_PHONE_NUMBER_ID=...
export WHATSAPP_WEBHOOK_URL=https://<region>-multitenant-pos-b8326.cloudfunctions.net/receiveWhatsappWebhook
export WHATSAPP_WEBHOOK_VERIFY_TOKEN=...    # the value set as the secret above
npm run whatsapp-webhook -- show            # where it points now
npm run whatsapp-webhook -- set             # point it at UzaPay
npm run whatsapp-webhook -- clear           # send events back to the app's default callback
```

Meta checks the URL with the verify token before accepting it, so deploy first. Template-approval
webhooks are not moved by the override and keep going to the app's default callback.

Until this is run, receipts still send; a receipt's status simply stops at *Sent*, and STOP replies
reach carerota's callback rather than UzaPay's.

## Rules the code enforces

- **Consent.** An automatic receipt goes only to an active customer whose record says they agreed,
  checked again at the moment of sending, so consent withdrawn after the sale still wins. Changing a
  customer's number clears consent unless the same correction records it again. A manual send is
  the customer's consent for that one receipt, and the sheet says so.
- **STOP.** A reply of STOP (or UNSUBSCRIBE, CANCEL, END, QUIT) suppresses that number for every
  business's receipts and is answered once; START lifts it.
- **At most three receipts per sale**, by every route together.
- **No phone number in the clear on delivery records.** `receipt_deliveries` holds the number
  masked and as a digest; an automatic send looks the number up on the customer at send time, and
  a manual one carries it only inside the task that sends it.
- **Offline.** A sale rung up offline sends its receipt when the sale reaches the server, not at the
  counter. A manual request made offline is queued on the till and sent when both the request and
  the sale have arrived (the send task retries for about a day).
- **Cost.** Every receipt sent is counted in `tenants/{tenantId}/whatsapp_usage/{yyyy-mm}`, ready
  for when Meta's cost is billed to businesses. Nothing bills it yet.

## Where things live

| What | Where |
| --- | --- |
| Setting per business | `tenants/{t}/configuration/e_receipts` (`whatsappEnabled`, `mode`, `format`) |
| Every receipt and its fate | `tenants/{t}/receipt_deliveries/{rd_...}` |
| Webhook lookup | `whatsapp_messages/{providerMessageId}` (server-only) |
| STOP list | `whatsapp_suppressions/{phone digest}` (server-only) |
| Automatic-reply throttle | `whatsapp_auto_replies/{phone digest}` (server-only) |
| Server code | `functions/src/whatsapp/` |
| Device code | `lib/whatsapp/`, and the till's post-sale message in `lib/checkout/checkout_cart_panel.dart` |

## Testing

- `npm test` in `functions/` covers the client, template parameters, the PDF, delivery decisions,
  retries, STOP and status ordering, with Meta replaced by a recording fetch.
- `flutter test test/whatsapp/ test/checkout/checkout_cart_panel_test.dart` covers the settings
  screen, the queued request and the till's post-sale message.
- End to end needs approved templates. Send a receipt to your own phone from a SIT build and watch
  its row on the WhatsApp tile move to *Sent*; after the override, to *Delivered* and *Read*. Reply
  STOP and check the next receipt is *Not sent - The customer replied STOP.*
