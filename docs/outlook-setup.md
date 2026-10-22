# Outlook.com / Hotmail setup

Notch Mail signs in to personal Microsoft accounts (Outlook.com, Hotmail, Live, MSN) with the **device-code flow**: it copies a short code to your clipboard and opens Microsoft's page, you paste the code and click **Accept**. You do this **once**; the sign-in renews itself as long as the app runs at least once every 90 days.

Like with Google, you bring your own (free) app registration, so your mail only ever flows between your Mac and Microsoft.

## 1. Register an app (5 minutes)

1. Sign in to <https://portal.azure.com> with your Microsoft account → **App registrations** → **New registration**.
2. Name: `Notch Mail`. Supported account types: **Personal Microsoft accounts only**. Redirect URI: leave empty. **Register**.
3. On the overview page, copy the **Application (client) ID**.
4. **Authentication** → **Advanced settings** → **Allow public client flows: Yes** → **Save**.

No client secret and no API permissions need to be added: Notch Mail asks for `Mail.ReadWrite`, `Mail.Send`, `User.Read` and `offline_access` at sign-in, and you approve them there.

## 2. Store the app ID

```sh
security add-generic-password -U -s notchmail.microsoft.clientid -a "$USER" -l "Notch Mail Microsoft app ID" -w
# paste the Application (client) ID when asked (twice)
```

On its next start Notch Mail copies it into its own Keychain item, like the Google items.

## 3. Connect

Envelope in the menu bar → **Connect Outlook / Hotmail…** → your browser opens `microsoft.com/link` and the code is already on your clipboard: paste it, pick your account, **Accept**. The menu then shows `Hotmail · you@…`. While waiting, the menu shows the code and can open the page again.

## What the permissions are used for

| Permission | Why |
|---|---|
| `Mail.ReadWrite` | Read unread inbox mail, mark read, move to Archive or Deleted Items (never deleted for good). |
| `Mail.Send` | Send your replies. |
| `User.Read` | Know which address is connected. |
| `offline_access` | Stay signed in without asking again. |

**Envelope → Disconnect Hotmail** forgets the sign-in. To revoke it at Microsoft as well: <https://account.live.com/consent/Manage>.
