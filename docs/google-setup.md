# Setting up your own Google OAuth client

Notch Mail talks to Gmail through **your own** Google Cloud OAuth client. This page walks you through creating one. It's free and takes about 10 minutes.

## Why your own client?

Notch Mail needs the `gmail.modify` scope (read, mark read, archive, trash, send replies). Google classifies it as **restricted**. A single shared client used by everyone would have to pass Google's restricted-scope verification, which includes a yearly security assessment by a Google-approved third party. That doesn't fit a free side project.

With your own client:

- nobody else (including the author) is ever involved; your Mac talks to Google directly,
- you can see and revoke exactly what was granted, in your own Google Cloud project,
- the only downside is this one-time setup and Google's "unverified app" notice on the sign-in page (it's *your* app, so that's expected).

> The Google Cloud console gets redesigned now and then. Menu names below match the **Google Auth Platform** layout (Branding / Audience / Clients / Data Access). If something is named differently for you, the concepts are the same.

## 1. Create a project and enable the Gmail and Drive APIs

1. Open <https://console.cloud.google.com/> and sign in with any Google account (it doesn't need to be the Gmail account you'll read).
2. Project picker (top left) → **New project**. Name it e.g. `notch-mail`. No organisation is needed.
3. **APIs & Services → Library**, search for **Gmail API**, click **Enable**. Do the same for **Google Drive API** (optional: it lets Claude find documents while drafting a reply; without it, replies still work).

## 2. Configure the consent screen

Go to **Google Auth Platform** (or **APIs & Services → OAuth consent screen**) and click **Get started**.

1. **App information**: app name `Notch Mail` (or anything), your email as support email.
2. **Audience**: choose one of these. This choice matters:

| Option | Who can use it | Refresh token lifetime | Good for |
|---|---|---|---|
| **Internal** | Only accounts in your Google Workspace organisation | Normal (doesn't expire on a timer) | Work Gmail on a Workspace domain, if your admin allows it |
| **External**, status **Testing** | Only the test users you list (max 100) | **Expires after 7 days** | Trying it out. You'll need to "Connect Gmail" again every week |
| **External**, status **In production** (unverified) | Anyone you give it to, max 100 users while unverified | Normal | Personal use long term. Google shows a "Google hasn't verified this app" screen at sign-in; click **Advanced → Go to Notch Mail (unsafe)** |

   - **Internal** only appears if your project belongs to a Workspace organisation. Personal `@gmail.com` accounts can't use it.
   - For a personal Gmail account, start with **External + Testing**. Once it works, you can press **Publish app** (Audience page) to move to *In production*. Don't submit it for verification; you don't need to for your own use.
   - If you work at a company with Workspace, check your IT policy before connecting a work account. Some admins block or must approve third-party OAuth apps.

3. **Contact information**: your email. Accept the policy and **Create**.

### Add yourself as a test user (External + Testing only)

**Audience → Test users → Add users**, and add the Gmail address(es) you want to read. Without this, Google rejects the sign-in with "Access blocked: … has not completed the Google verification process".

### Add the scopes

**Data Access → Add or remove scopes**, and add:

| Scope | Why |
|---|---|
| `https://www.googleapis.com/auth/gmail.modify` | Read unread inbox mail, mark read, archive (remove `INBOX` label), move to Trash, send your replies. Can't permanently delete. |
| `https://www.googleapis.com/auth/drive.readonly` | Optional. Lets Claude search and read your Drive files while drafting a reply. Read-only. |
| `openid` | Standard sign-in. |
| `.../auth/userinfo.email` (`email`) | So Notch Mail knows which address it connected (shown in the menu). |

Notch Mail asks for exactly these four at sign-in. Listing them here too keeps Google's consent screen clean. If you leave `gmail.modify` unticked on Google's page, Notch Mail will tell you it wasn't allowed; `drive.readonly` can be unticked freely.

## 3. Create the OAuth client

1. **Clients → Create client** (or **Credentials → Create credentials → OAuth client ID**).
2. Application type: **Desktop app**. Name: `Notch Mail`.
3. **Create**. Copy the **Client ID** (ends in `.apps.googleusercontent.com`) and the **Client secret**.

No redirect URI to configure: desktop clients allow the loopback redirect (`http://127.0.0.1:<random port>`) that Notch Mail uses.

> For desktop apps Google doesn't treat the "client secret" as truly secret (it can't be kept secret inside an app). It's still yours, though: don't paste it into issues, commits or screenshots.

## 4. Store the client ID and secret in your Keychain

Notch Mail reads two generic-password items from your **login keychain**. The **account** must be your macOS short user name (what `echo $USER` prints):

| Keychain service | Account | Value |
|---|---|---|
| `notchmail.google.clientid` | your macOS user name (`$USER`) | Client ID |
| `notchmail.google.secret` | your macOS user name (`$USER`) | Client secret |

Run these in Terminal. Putting `-w` **last** makes `security` prompt for the value, so it doesn't end up in your shell history:

```sh
security add-generic-password -U -s notchmail.google.clientid -a "$USER" -l "Notch Mail Google client ID" -w
# paste YOUR_CLIENT_ID.apps.googleusercontent.com when asked (twice)

security add-generic-password -U -s notchmail.google.secret -a "$USER" -l "Notch Mail Google client secret" -w
# paste YOUR_CLIENT_SECRET when asked (twice)
```

(`-U` updates an existing item, so you can rerun these to change the values.)

To check the items exist **without printing the secret**:

```sh
security find-generic-password -s notchmail.google.clientid -a "$USER" >/dev/null && echo "client ID: ok"
security find-generic-password -s notchmail.google.secret   -a "$USER" >/dev/null && echo "secret: ok"
```

On its next start, Notch Mail copies these items into a single Keychain item it creates itself (`notchmail.secrets`). macOS asks once per item whether `NotchMail` may read it for that copy; choose **Always Allow**. After that nothing asks again, because apps aren't asked about their own items. The single items can then be deleted, or kept as a backup.

## 5. Connect

1. Click the envelope icon in the menu bar → **Connect Gmail…**
2. Your browser opens Google's sign-in. Pick the account, and on the "unverified app" screen choose **Advanced → Go to Notch Mail**.
3. Leave all permissions ticked and continue. The browser tab says "Gmail is connected" and you can close it; the menu now shows `Gmail · you@…` and when it last checked.

After connecting, Notch Mail stores one more item itself. You don't need to create it:

| Keychain service | Account | Value |
|---|---|---|
| `notchmail.google.refresh` | the connected Gmail address | Google refresh token |

## Disconnecting and cleaning up

- **Envelope → Disconnect Gmail** revokes the token at Google and deletes `notchmail.google.refresh`.
- You can also revoke access at <https://myaccount.google.com/connections>.
- To remove your client credentials:
  ```sh
  security delete-generic-password -s notchmail.google.clientid -a "$USER"
  security delete-generic-password -s notchmail.google.secret   -a "$USER"
  ```
- Delete the Google Cloud project if you don't need it any more.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Menu shows "Google client ID or secret missing from the Keychain" | The Keychain items don't exist, or their account isn't exactly `$USER`. |
| "Access blocked … has not completed the Google verification process" | External + Testing, and the address isn't in **Test users**. |
| "Gmail access wasn't allowed on Google's page" | The Gmail checkbox was unticked on the consent page. Connect again and leave it ticked. |
| Menu shows "Sign-in expired, connect again" (often after 7 days) | External + Testing. Publish the app (In production) or use Internal, then connect again. |
| `redirect_uri_mismatch` | The client type isn't **Desktop app**. Create a new Desktop client. |
| "Google didn't return a refresh token" | Rare. Remove Notch Mail at <https://myaccount.google.com/connections> and connect again. |

## Anthropic API key (for reply drafts)

Reply drafts are written by Claude with your own key from <https://console.anthropic.com> (Settings → API keys). Store it like the Google items:

```sh
security add-generic-password -U -s notchmail.anthropic -a "$USER" -l "Notch Mail Anthropic API key" -w
# paste your sk-ant-… key when asked (twice)
```

If your key belongs to an organization but isn't tied to one workspace, the API also needs the workspace ID (`wrkspc_…`, from the Console URL). Optional:

```sh
security add-generic-password -U -s notchmail.anthropic.workspace -a "$USER" -l "Notch Mail Anthropic workspace" -w
```

Replies are signed with your macOS full name. To use a different name: `defaults write io.github.felixsbuehrm.notchmail reply.name "Your Name"`.

Without a key, Reply still works: type the reply yourself instead of pressing **Write**.
