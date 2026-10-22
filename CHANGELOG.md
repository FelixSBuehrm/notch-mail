# Changelog

All notable changes. Dates are when they landed on `main`.

## 0.1.0 · 2026-10-23 · first public version

- **Notch:** new mail slides out of the notch; rest the pointer to open it; scrollable list of unread mail (10/20/50); enlarge button; hidden from screen sharing.
- **Accounts:** Gmail (Google OAuth, loopback + PKCE) and Outlook.com / Hotmail (Microsoft Graph, device-code sign-in), side by side.
- **Actions:** archive, delete (recoverable), mark read, Remind me (1 hour, this evening, tomorrow).
- **Reply with Claude:** instruction → editable draft → Send with 5 s undo; read-only Gmail/Drive or Outlook lookups; real recipient shown, Reply-To warning.
- **Reading:** HTML mail with its own layout (JavaScript off, remote content blocked until "Load images"); folded quotes and short links in plain text.
- **Login codes:** detected in English and German code mails, shown big, copied with one click, listed in the menu bar for 15 minutes.
- **Secrets:** one app-owned Keychain item; nothing on disk; no server, analytics or telemetry.
- **Look:** app icon, demo GIF and screenshots made from demo mail (`scripts/screenshots/`).
