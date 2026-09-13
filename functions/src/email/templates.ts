import {
  BRAND_NAME,
  BrandedEmail,
  renderBrandedEmailHtml,
  renderBrandedEmailText,
} from "./branding";

/**
 * What each of the four outgoing emails says.
 *
 * **Content only.** Nothing here decides a colour, a width or a font; that is
 * `branding.ts`, and the split is the point - a wording change is reviewable
 * without reading a table layout, and a design change lands in one file rather
 * than four.
 *
 * **Nothing in a rendered email may name a person, a business or a role.** The
 * delivery records deliberately carry only an HMAC of the recipient, and the
 * staff task holds a tenant id it never prints. An email that greeted somebody
 * by name would put back exactly what `recipientHash.ts` takes out, so every
 * template below addresses the reader as "you" and describes the action rather
 * than the account.
 *
 * **No template states a lifetime it cannot prove.** The invitation has one in
 * source - `INVITATION_LIFETIME_MILLISECONDS`, seven days - and says so. The
 * Firebase action links do not: their expiry is a console setting this
 * repository does not own, so those templates say the link is single-use, which
 * the code does guarantee, and leave the clock unstated.
 */

export interface RenderedEmail {
  subject: string;
  html: string;
  text: string;
}

function render(subject: string, email: BrandedEmail): RenderedEmail {
  return {
    subject,
    html: renderBrandedEmailHtml(email),
    text: renderBrandedEmailText(email),
  };
}

export function passwordResetEmail(actionUrl: string): RenderedEmail {
  return render(`Reset your ${BRAND_NAME} password`, {
    preheader: "Choose a new password. The link opens once and then expires.",
    eyebrow: "Account security",
    title: "Reset your password",
    lead: "Someone asked to reset the password for the " + BRAND_NAME +
      " account at this address. Choose a new one and you are back in.",
    body: [
      "The link below opens once. Following it retires every reset link " +
      "issued before it, including any you requested earlier today.",
    ],
    action: {label: "Choose a new password", url: actionUrl},
    notice: {
      tone: "warning",
      title: "Did not ask for this?",
      body: "Then ignore this message and nothing changes - your current " +
        "password keeps working and no one can reach the account through " +
        "this link without opening this inbox. If it keeps arriving, tell " +
        "whoever administers your business.",
    },
    footnote: "You are receiving this because a password reset was requested " +
      "for this email address. Nothing has changed on the account yet.",
  });
}

export function accountVerificationEmail(actionUrl: string): RenderedEmail {
  return render(`Verify your ${BRAND_NAME} email address`, {
    preheader: "One tap confirms this address and the app carries on.",
    eyebrow: "Finish signing up",
    title: "Confirm your email address",
    lead: "Confirming this address is the last step before " + BRAND_NAME +
      " can secure the account and let you set up your business.",
    body: [
      "On a phone with the app installed, the button opens the app straight " +
      "onto the next step. Anywhere else it opens a page that tells you to " +
      "switch back - the app notices the confirmation on its own either way.",
    ],
    action: {label: "Verify this address", url: actionUrl},
    notice: {
      tone: "info",
      title: "Next in the app",
      body: "Tell us about your business, and you can start selling. There " +
        "is nothing else to fill in on the web.",
    },
    footnote: "You are receiving this because this address was used to " +
      "create a " + BRAND_NAME + " account. If that was not you, ignore " +
      "this message and the account stays unverified and unusable.",
  });
}

export function platformAlertEmail(
  actionUrl: string,
  severity: "critical" | "attention",
  alertType: string
): RenderedEmail {
  const critical = severity === "critical";
  return render(
    critical ?
      `${BRAND_NAME}: critical platform alert` :
      `${BRAND_NAME}: platform alert needs review`,
    {
      preheader: critical ?
        "A critical platform alert is waiting on an operator." :
        "A platform alert is waiting on an operator.",
      eyebrow: "Platform operations",
      title: critical ?
        "A critical alert needs an operator" :
        "An alert needs an operator",
      lead: "Something on the platform has raised an alert that only a " +
        "platform administrator can clear. The detail stays in the app.",
      body: [
        "This message names the alert and nothing else. No tenant, no " +
        "account and no reason for the alert leaves the platform by email.",
      ],
      action: {label: "Open the operator dashboard", url: actionUrl},
      notice: {
        tone: critical ? "critical" : "warning",
        title: critical ? "Critical" : "Needs attention",
        body: `Alert type: ${alertType}`,
      },
      footnote: "You are receiving this because your account holds a " +
        "platform administrator grant. Alerts are visible only to accounts " +
        "that hold one.",
    }
  );
}

/**
 * **Rewritten 2026-09-08, because it described a journey that did not exist.**
 * It used to give three steps ending "open the business selector; the
 * invitation is waiting there", and for every reader who got the
 * password-setting version of it the invitation was not waiting there and could
 * not be put there: the app refused those acceptances and told them to use this
 * link instead, and this link opened a web page that told them to accept in the
 * app. The link now opens the app, and the app can accept without it, so the
 * steps below are ones a reader can actually walk.
 *
 * @param credentialBootstrapRequired The recipient has no password yet, so the
 *   link is a credential-setup link that continues to the invitation. Saying so
 *   is the difference between a page the reader expected and one that looks
 *   like the wrong email arrived.
 */
export function staffInvitationEmail(
  actionUrl: string,
  credentialBootstrapRequired: boolean
): RenderedEmail {
  const steps = credentialBootstrapRequired ?
    [
      "Set a password for this email address.",
      `Install ${BRAND_NAME} if it is not on this phone already.`,
      "Sign in with this address and the password you just set. The " +
      "invitation is on the first screen.",
    ] :
    [
      `Open ${BRAND_NAME} and sign in with this same email address.`,
      "Accept the invitation, which is waiting on the first screen.",
    ];
  return render(`You have been invited to a ${BRAND_NAME} workspace`, {
    preheader: "Accept the invitation in the app to start working.",
    eyebrow: "Staff invitation",
    title: "You have been invited to a business",
    lead: credentialBootstrapRequired ?
      "Someone has added you to their business on " + BRAND_NAME + ". Set a " +
      "password first, then accept the invitation in the app." :
      "Someone has added you to their business on " + BRAND_NAME + ". Accept " +
      "the invitation in the app and you can start work.",
    steps,
    body: [
      credentialBootstrapRequired ?
        "The button asks for a new password first, and continues to the " +
        "invitation once it is set. Wherever it lands you, the invitation " +
        "itself is in the app, and signing in with this address is all it " +
        "takes to reach it." :
        "On a phone with the app installed, the button opens the app on the " +
        "invitation. Anywhere else it opens a page describing what to do - " +
        "the invitation is in the app either way, and signing in with this " +
        "address is all it takes to reach it.",
    ],
    action: {
      label: credentialBootstrapRequired ?
        "Set your password" :
        "Open the invitation",
      url: actionUrl,
    },
    notice: {
      tone: "primary",
      title: "Good for seven days",
      body: "After that the invitation stops working and whoever invited you " +
        "can send a fresh one. Accepting is the only thing that admits you - " +
        "nobody can add you to a business you have not agreed to join.",
    },
    footnote: "You are receiving this because this address was invited to a " +
      "business on " + BRAND_NAME + ". If you were not expecting it, ignore " +
      "this message and no one is given access to anything.",
  });
}
