import { config } from "../config.mjs";

/// Public Privacy Policy and Terms pages required for App Store / IAP review.
/// Hosted on the API origin so paywall links resolve without a separate marketing site.

export function servePrivacyPolicy(request, response) {
  sendHTML(request, response, privacyHTML());
}

export function serveTermsOfUse(request, response) {
  sendHTML(request, response, termsHTML());
}

export function serveSupport(request, response) {
  sendHTML(request, response, supportHTML());
}

function sendHTML(request, response, html) {
  const body = Buffer.from(html, "utf8");
  response.writeHead(200, {
    "Content-Type": "text/html; charset=utf-8",
    "Content-Length": body.length,
    "Cache-Control": "public, max-age=300",
    "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer"
  });
  // App Store / link checkers often probe with HEAD; return headers only.
  if (request.method === "HEAD") {
    response.end();
    return;
  }
  response.end(body);
}

function layout(title, body) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${title} — SceneMe</title>
  <style>
    :root { color-scheme: dark; }
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #0c0c0e;
      color: #f2efe8;
      line-height: 1.55;
    }
    main { max-width: 720px; margin: 0 auto; padding: 48px 22px 80px; }
    h1 { font-size: 1.75rem; margin: 0 0 8px; letter-spacing: -0.02em; }
    h2 { font-size: 1.1rem; margin: 28px 0 10px; color: #dfc078; }
    p, li { color: #c9c4ba; font-size: 0.95rem; }
    .meta { color: #8a857c; font-size: 0.85rem; margin-bottom: 28px; }
    a { color: #dfc078; }
    ul { padding-left: 1.2rem; }
  </style>
</head>
<body>
  <main>
    <h1>${title}</h1>
    <p class="meta">SceneMe, a Zevynta Labs LLC product · Last updated October 13, 2026</p>
    ${body}
  </main>
</body>
</html>`;
}

function privacyHTML() {
  return layout("Privacy Policy", `
    <p>SceneMe is a product operated by Zevynta Labs LLC (“Zevynta Labs”, “we”, “us”). SceneMe helps you place yourself into cinematic scenes using photos you choose. This policy explains what we collect and why.</p>

    <h2>Information we collect</h2>
    <ul>
      <li><strong>Account data</strong> — name, email, authentication identifiers, and an encrypted Apple revocation credential when you sign in with Apple.</li>
      <li><strong>Photos you upload</strong> — images you select to generate scenes, optional companion photos, and derived results.</li>
      <li><strong>Generation inputs</strong> — scene choices, time of day, weather, pose, custom scene text, spoken lines for Talking video, and similar creative settings.</li>
      <li><strong>Usage data</strong> — generation history, subscription status from Apple, and basic operational logs needed to run the service.</li>
    </ul>

    <h2>How we use information</h2>
    <ul>
      <li>To generate images and short videos you request (including optional AI text-to-speech for Talking clips).</li>
      <li>To operate accounts, subscriptions, restore purchases, and provide support.</li>
      <li>To protect the service, enforce plan limits, diagnose failures, and provide support.</li>
    </ul>

    <h2>AI processing and consent</h2>
    <p>SceneMe asks for your explicit permission before sending personal content to third-party AI providers. When you allow it, <strong>OpenAI</strong> receives the selected photo, optional companion photo, and user-written text for safety screening; OpenAI also receives custom-scene text for enhancement only when you tap “Improve with OpenAI.” After safety screening, <strong>fal.ai</strong> receives the selected photo, optional companion photo, and the instructions needed to generate images, videos, or optional speech. Our cloud host stores account records, uploads, and results so the app can operate. We do not sell this content or use it for cross-app tracking.</p>
    <p>You can decline without sharing content. You can also withdraw permission at any time in Profile → AI Data Sharing; SceneMe will stop sending new requests unless you grant permission again.</p>

    <h2>Retention</h2>
    <p>We keep your account record, uploaded photos, and creative inputs until you delete your account. Generated results remain in history until you delete that result or your account. In-app account deletion removes the associated account, uploads, generations, usage records, and stored Apple revocation credential from systems we control. Processors may retain short-lived operational or security copies under their own retention policies; requests already in progress may finish before deletion propagates.</p>

    <h2>Your choices</h2>
    <ul>
      <li>You control which photos you upload.</li>
      <li>You can review or withdraw AI processing permission in Profile.</li>
      <li>You can delete your account from Profile.</li>
      <li>You manage subscriptions in Apple ID settings. Deleting a SceneMe account does not cancel an Apple subscription.</li>
    </ul>

    <h2>Children</h2>
    <p>SceneMe is not directed to children under 13. Do not use the app if you are under 13.</p>

    <h2>Tracking</h2>
    <p>We do not use your data for cross-app tracking or sell personal information.</p>

    <h2>Contact</h2>
    <p>Questions: <a href="mailto:support@sceneme.app">support@sceneme.app</a></p>
    <p>Company website: <a href="https://zevyntalabs.com/">zevyntalabs.com</a></p>
    <p>Also see our <a href="${config.publicBaseURL}/terms">Terms of Use</a>.</p>
  `);
}

function termsHTML() {
  return layout("Terms of Use", `
    <p>These Terms are an agreement between you and Zevynta Labs LLC, the operator of SceneMe. By using SceneMe you agree to these Terms. If you do not agree, do not use the app.</p>

    <h2>The service</h2>
    <p>SceneMe generates AI images and short videos that place you (and optional companions) into themed scenes. Results are creative interpretations and may not be perfect likenesses. Talking videos may include synthesized speech of text you provide.</p>

    <h2>Eligibility &amp; accounts</h2>
    <p>You must be at least 13 and able to form a binding contract. You are responsible for activity under your account.</p>

    <h2>Your content</h2>
    <p>You retain rights to photos you upload. You grant us a limited license to process that content solely to provide the features you request. You must only upload images you have the right to use, and you must not upload illegal, harmful, or infringing content.</p>

    <h2>AI results</h2>
    <p>Outputs are AI-generated. Do not present them as unaltered photographs when that would mislead others in a harmful way. Do not use SceneMe to create illegal deepfakes, non-consensual intimate imagery, or content that violates others’ rights.</p>

    <h2>Subscriptions</h2>
    <p>Paid plans are billed through Apple In-App Purchase. Prices are shown in the app and charged by Apple. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel in iPhone Settings → Apple ID → Subscriptions. Free tiers have limited generations; paid tiers unlock higher limits and Pro features such as Video Director.</p>

    <h2>Acceptable use</h2>
    <ul>
      <li>No abuse, reverse engineering, or attempts to bypass usage limits or paywalls.</li>
      <li>No uploading of CSAM or other prohibited material.</li>
      <li>No harassment, hate, or fraudulent impersonation.</li>
    </ul>

    <h2>Disclaimer</h2>
    <p>The service is provided “as is.” We do not guarantee uninterrupted availability or perfect face fidelity. To the fullest extent permitted by law, we disclaim warranties and limit liability for indirect or consequential damages.</p>

    <h2>Termination</h2>
    <p>We may suspend accounts that violate these Terms. You may delete your account in the app.</p>

    <h2>Contact</h2>
    <p><a href="mailto:support@sceneme.app">support@sceneme.app</a></p>
    <p>Company website: <a href="https://zevyntalabs.com/">zevyntalabs.com</a></p>
    <p>Privacy details: <a href="${config.publicBaseURL}/privacy">Privacy Policy</a>.</p>

    <p>© 2026 Zevynta Labs LLC. All rights reserved.</p>
  `);
}

function supportHTML() {
  return layout("SceneMe Support", `
    <p>Need help with SceneMe? Contact Zevynta Labs LLC at <a href="mailto:support@sceneme.app">support@sceneme.app</a>.</p>

    <h2>When you contact us</h2>
    <p>Include your SceneMe account email, app version, device model, iOS version, and a short description of what happened. Do not email passwords, authentication codes, payment credentials, private photos, or signed media links.</p>

    <h2>Generation help</h2>
    <ul>
      <li>If a generation is still processing, keep the job in History and try again after reconnecting.</li>
      <li>If a generation fails, use the in-app retry option. SceneMe does not consume an image allowance for a job the backend records as failed.</li>
      <li>For a privacy or safety concern, include “Privacy” or “Safety” in the email subject.</li>
    </ul>

    <h2>Subscriptions</h2>
    <p>Purchases are billed by Apple. Use Restore Purchases in SceneMe if an active purchase is missing. Manage or cancel a subscription in Apple ID settings. Deleting your SceneMe account does not cancel an Apple subscription.</p>

    <h2>Account and privacy</h2>
    <p>Account deletion is available in SceneMe under Profile. See the <a href="${config.publicBaseURL}/privacy">Privacy Policy</a> and <a href="${config.publicBaseURL}/terms">Terms of Use</a> for more information.</p>

    <p>Company website: <a href="https://zevyntalabs.com/">zevyntalabs.com</a></p>
  `);
}
