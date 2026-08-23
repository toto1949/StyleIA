import { config } from "../config.mjs";

/// Public Privacy Policy and Terms pages required for App Store / IAP review.
/// Hosted on the API origin so paywall links resolve without a separate marketing site.

export function servePrivacyPolicy(request, response) {
  sendHTML(request, response, privacyHTML());
}

export function serveTermsOfUse(request, response) {
  sendHTML(request, response, termsHTML());
}

function sendHTML(request, response, html) {
  const body = Buffer.from(html, "utf8");
  response.writeHead(200, {
    "Content-Type": "text/html; charset=utf-8",
    "Content-Length": body.length,
    "Cache-Control": "public, max-age=300"
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
    <p class="meta">SceneMe, a Zevynta Labs LLC product · Last updated August 23, 2026</p>
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
      <li><strong>Account data</strong> — email and authentication identifiers when you sign in with email, Apple, or Google.</li>
      <li><strong>Photos you upload</strong> — images you select to generate scenes, optional companion photos, and derived results.</li>
      <li><strong>Generation inputs</strong> — scene choices, time of day, weather, pose, custom scene text, spoken lines for Talking video, and similar creative settings.</li>
      <li><strong>Usage data</strong> — generation history, subscription status from Apple, and basic operational logs needed to run the service.</li>
      <li><strong>Device / app data</strong> — standard diagnostics needed for crash fixing and delivery (not used for cross-app tracking).</li>
    </ul>

    <h2>How we use information</h2>
    <ul>
      <li>To generate images and short videos you request (including optional AI text-to-speech for Talking clips).</li>
      <li>To operate accounts, subscriptions, restore purchases, and provide support.</li>
      <li>To improve reliability, safety, and product quality.</li>
    </ul>

    <h2>Processors</h2>
    <p>We use infrastructure and AI providers to process requests and generate media (for example cloud hosting, OpenAI for optional template improvement, and fal.ai models for image and video generation). Content is processed to fulfill your request and is not sold.</p>

    <h2>Retention</h2>
    <p>Uploaded photos and generated results are kept so you can view history and re-use features such as Animate. You may delete your account in the app, which removes associated account data we control. Cached CDN media may expire according to provider limits.</p>

    <h2>Your choices</h2>
    <ul>
      <li>You control which photos you upload.</li>
      <li>You can delete your account from Profile.</li>
      <li>You manage subscriptions in Apple ID settings.</li>
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
