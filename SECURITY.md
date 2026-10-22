# Security Policy

Notch Mail handles mail and OAuth tokens, so security reports are very welcome.

## Reporting a vulnerability

**Please don't open a public issue.** Instead, report it privately:

1. Go to the **Security** tab of this repository.
2. Click **Report a vulnerability** (GitHub private vulnerability reporting).

Please include what you found, how to reproduce it, and what an attacker could do with it. You'll get an answer as soon as possible, usually within a week. This is a personal project, so there's no bug bounty, but you'll be credited in the fix unless you'd rather not be.

## Supported versions

Only the latest commit on `main` (and, once there are releases, the latest release) gets fixes.

## Scope

Especially interesting:

- Anything that leaks mail content, tokens, API keys or client secrets (to disk, logs, other processes or the network).
- Problems in the OAuth flow (loopback receiver, PKCE, state handling).
- Ways for a malicious email to do more than display text and safe links (the HTML view is meant to run no JavaScript and load nothing remote until "Load images").
- Prompt injection: a mail or a looked-up document that gets Claude to put something harmful or private into a draft, or to misuse its read-only tools.
- Problems in the Microsoft device-code sign-in or refresh-token handling.
- Anything that could send mail you didn't confirm, or to someone other than the recipient shown.

Out of scope: issues that need an attacker who already controls your user account or Keychain, and the fact that each user's own Google OAuth client is "unverified" (that's by design, see the README).

## If you leaked your own secrets

If you accidentally pasted your Google client secret, a refresh token or an API key into an issue, PR or commit: delete or rotate it right away (Google Cloud Console → Credentials → reset secret; Google Account → Security → Third-party access → remove the app).
