# Getting started

From zero to "mail slides out of my notch" in about 20 minutes, most of it one-time account setup.

**You need:** a Mac with macOS 15 or later (a notched MacBook looks best), and Gmail and/or Outlook.com / Hotmail. That's it: no Xcode, no paid accounts.

---

## 1. Install (2 minutes)

Open **Terminal** and run:

```sh
xcode-select --install          # only if you've never installed the Command Line Tools
git clone https://github.com/FelixSBuehrm/notch-mail.git
cd notch-mail
scripts/install.sh
```

`install.sh` builds the app, copies it to `/Applications/NotchMail.app` and starts it. You'll see:

- an **envelope icon** in the menu bar: that's Notch Mail's only control,
- a **demo mail** sliding out of the notch. Rest the pointer on it to open it.

Notch Mail adds itself to **Login Items**, so it starts with your Mac. Turn that off any time: envelope → **Open at Login**.

**Updating later:** `git pull && scripts/install.sh`.

## 2. Connect Gmail (10 minutes, once)

You create your own free Google "app" so your mail only flows between your Mac and Google. Full walkthrough of every choice: **[google-setup.md](google-setup.md)**. In short:

1. [console.cloud.google.com](https://console.cloud.google.com): new project → enable the **Gmail API** (and optionally the **Google Drive API**).
2. **OAuth consent screen**: add yourself as a test user and publish it, so you don't have to reconnect weekly.
3. **Credentials → Create OAuth client → Desktop app**, then store the ID and secret:
   ```sh
   security add-generic-password -U -s notchmail.google.clientid -a "$USER" -w   # paste the client ID
   security add-generic-password -U -s notchmail.google.secret   -a "$USER" -w   # paste the client secret
   ```
4. Envelope → **Connect Gmail…** → pick your account in the browser → **Allow**.

## 3. Connect Outlook.com / Hotmail (5 minutes, once)

Full walkthrough: **[outlook-setup.md](outlook-setup.md)**. In short:

1. [portal.azure.com](https://portal.azure.com) → **App registrations → New registration** → "Personal Microsoft accounts only".
2. **Authentication → Allow public client flows → Yes**.
3. Store the Application (client) ID:
   ```sh
   security add-generic-password -U -s notchmail.microsoft.clientid -a "$USER" -w
   ```
4. Envelope → **Connect Outlook / Hotmail…**. A code is copied and Microsoft's page opens: paste it, pick your account, **Accept**. You only do this once.

## 4. Claude drafts (2 minutes, optional)

Get an API key at [console.anthropic.com](https://console.anthropic.com) and store it:

```sh
security add-generic-password -U -s notchmail.anthropic -a "$USER" -w
```

A typical draft costs well under a cent. Without a key, Reply still works; you just type the reply yourself. Details: [google-setup.md → Anthropic API key](google-setup.md#anthropic-api-key-for-reply-drafts).

## 5. The first time it starts after setup

macOS asks whether **NotchMail** may use the items you stored. Choose **Always Allow** (it asks for your Mac password). Notch Mail then copies everything into one Keychain item of its own. After that you're asked once per new build, until there's a signed release.

---

## Using it

| You want to… | Do this |
|---|---|
| See unread mail | Rest the pointer on the notch for a moment |
| Open a mail | Click it in the list, or rest on a mail that just popped up |
| Archive / delete / mark read | The buttons at the bottom. Delete is recoverable (Trash / Deleted Items) |
| Have it come back later | **Remind** → 1 hour, this evening, or tomorrow morning |
| Reply | **Reply** → type what it should say → **Write** (or just type the reply) → **Send** (⌘↩) → 5 s to **Undo** |
| Read a long mail | The expand button at the top right makes the notch bigger |
| See pictures in a mail | **Load images** under the mail (off by default, so senders can't track you) |
| Copy a login code | **Copy code** in the mail, or click it in the envelope menu |
| Show more or fewer mails | Envelope → **List shows** → 10 / 20 / 50 |

## Troubleshooting

| Symptom | Fix |
|---|---|
| No envelope in the menu bar | The menu bar may be full (it hides items behind the notch). Quit a few menu-bar apps, or check `pgrep -l NotchMail`. |
| "Google client ID or secret missing" | The Keychain items don't exist, or the account isn't exactly `$USER`. Rerun the `security` commands. |
| Gmail asks to reconnect every week | Your consent screen is External + Testing. See [google-setup.md](google-setup.md). |
| Password prompts after every update | Expected without a signed release: choose **Always Allow** once per build. |
| A mail looks empty or broken | Try **Load images**; some mails are only pictures. Plain-text mails never load anything. |
| The notch doesn't open | Keep the pointer still on it for a moment; quick passes are ignored on purpose. |

Still stuck? [Open an issue](https://github.com/FelixSBuehrm/notch-mail/issues/new/choose).
