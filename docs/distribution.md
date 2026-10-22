# Distribution plan: getting a downloadable Notch Mail onto other Macs

Status: **plan**. Today Notch Mail is build-from-source only. This page describes how to ship a download that anyone can double-click, and in what order.

Facts checked in October 2026. Prices and Apple's tooling change, so re-check the linked sources before paying for anything.

## TL;DR: recommended path

| Step | What | Cost | Who it unlocks |
|---|---|---|---|
| 0 | Build from source (`scripts/install.sh`) | free | Tinkerers with Command Line Tools |
| 1 | Join the **Apple Developer Program**, create a **Developer ID Application** certificate | **US$99 / year** | Everything below |
| 2 | Local `scripts/release.sh`: sign with hardened runtime, notarize with `notarytool`, staple, package as **zip + DMG** | free | People download it, drag it to Applications, done. No warnings |
| 3 | Same steps in **GitHub Actions** on a macOS runner, triggered by a `v*` tag, uploading to a GitHub Release | free for public repos | Repeatable releases without your laptop |
| 4 | **Own Homebrew tap** (`brew install --cask felixsbuehrm/tap/notch-mail`) | free | Developers who live in Terminal |
| 5 | *(optional)* **Sparkle** in-app updates | free | People who never check GitHub |

Do 1 → 2 by hand once (so you understand every step and see notarization errors locally), then automate in 3. Skip shipping unsigned builds to non-technical people: the macOS 15+ Gatekeeper flow for unsigned apps is a poor first impression (see below).

## Why signing matters for this app in particular

Two reasons, one obvious and one not:

1. **Gatekeeper.** A downloaded app that isn't signed with a Developer ID *and* notarized is blocked on first launch.
2. **Keychain prompts.** Notch Mail keeps its tokens and your client secret in the Keychain. macOS ties "Always Allow" to the app's **code signature** (its designated requirement). Ad-hoc signatures change with every build, so users would be asked again after every update. A Developer ID signature is stable across versions (same Team ID + bundle ID), so the answer sticks. The source build uses `scripts/signing.sh` (a local self-signed identity) today; in practice macOS still asks once per new build for the app's Keychain item, because without a Team ID the approval is tied to the build. A Developer ID signature fixes that.

   Note: switching from the local self-signed identity to Developer ID changes the signature **once**. Expect one more round of Keychain prompts after the first signed release.

## 1. Apple Developer Program

- **Cost:** US$99 per year (shown in local currency in some regions). Source: <https://developer.apple.com/programs/>. Fee waivers exist only for some nonprofits, schools and government entities.
- **Enroll as an individual** with your Apple Account. Your legal name is shown as the "developer" in Gatekeeper dialogs and in `codesign -dv` output. (Enrolling as an organisation needs a D-U-N-S number and shows the company name. Only do that if it's the company's app.)
- **Create the certificate:** Certificates, Identifiers & Profiles → Certificates → `+` → **Developer ID Application**. Only the *Account Holder* can create Developer ID certificates. Make a CSR in Keychain Access (Certificate Assistant → Request a Certificate from a Certificate Authority), upload it, download the `.cer`, double-click it to install. Then export certificate + private key as a password-protected **`.p12`** for CI. Keep it out of the repo (`.gitignore` already blocks `*.p12`).
- **Notarization credentials:** prefer an **App Store Connect API key** (Users and Access → Integrations → Team Keys, role *Developer*) over Apple ID + app-specific password. You get a `.p8` file (downloadable once), a **Key ID** and an **Issuer ID**.

You don't need a provisioning profile: Notch Mail doesn't use App Sandbox, iCloud or push, so no restricted entitlements.

## 2. Sign → notarize → staple → package

### Bundle ID

The bundle ID is **`io.github.felixsbuehrm.notchmail`** (`AppIdentity.bundleID` and `scripts/bundle.sh`). Keep it: changing it resets the app's `UserDefaults` (connected addresses, reminders) and its Keychain approvals.

### Sign with hardened runtime

Notarization requires a Developer ID signature, the **hardened runtime** and a **secure timestamp**, and no `get-task-allow` entitlement:

```sh
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  build/NotchMail.app
codesign --verify --strict --verbose=2 build/NotchMail.app
```

Notch Mail needs no hardened-runtime exceptions: it makes outgoing HTTPS calls and listens on `127.0.0.1` for the OAuth redirect, and neither needs entitlements without App Sandbox. If you ever add App Sandbox you'd need `com.apple.security.network.client` and `com.apple.security.network.server`.

`scripts/bundle.sh` currently always calls `scripts/signing.sh`. For releases, let it take the identity from an environment variable (e.g. `SIGN_IDENTITY`) and fall back to the local identity when it's unset.

### Notarize and staple

Store the API key once in your login keychain (so it never sits in your shell history or the repo):

```sh
xcrun notarytool store-credentials notchmail-notary \
  --key ~/private/AuthKey_KEYID.p8 --key-id KEYID --issuer ISSUER-UUID
```

Then per release:

```sh
# Notarize the app (notarytool accepts .zip, .dmg and .pkg, not a bare .app)
ditto -c -k --keepParent build/NotchMail.app build/NotchMail-notarize.zip
xcrun notarytool submit build/NotchMail-notarize.zip --keychain-profile notchmail-notary --wait
xcrun stapler staple build/NotchMail.app            # a .zip can't be stapled, the .app can

# Distribution zip (for Homebrew and GitHub Releases)
ditto -c -k --keepParent build/NotchMail.app build/NotchMail-1.0.0.zip

# Optional DMG for humans: sign, notarize and staple it too
hdiutil create -volname "Notch Mail" -srcfolder build/NotchMail.app -ov -format UDZO build/NotchMail-1.0.0.dmg
codesign --sign "Developer ID Application: YOUR NAME (TEAMID)" --timestamp build/NotchMail-1.0.0.dmg
xcrun notarytool submit build/NotchMail-1.0.0.dmg --keychain-profile notchmail-notary --wait
xcrun stapler staple build/NotchMail-1.0.0.dmg

# Check what Gatekeeper will say
spctl --assess --type execute --verbose build/NotchMail.app
```

If notarization fails, `xcrun notarytool log <submission-id> --keychain-profile notchmail-notary` shows why (usually a missing `--options runtime` or `--timestamp`).

**Zip or DMG?** Both. The zip is what Homebrew and Sparkle want. A DMG with a shortcut to `/Applications` is friendlier for most people. Start with the zip; add a pretty DMG (e.g. with [`create-dmg`](https://github.com/create-dmg/create-dmg)) when there's time.

## 3. Automate in GitHub Actions

A draft workflow is in [`docs/examples/release.yml`](examples/release.yml). It isn't active on purpose. Copy it to `.github/workflows/` once steps 1–2 work locally.

What it does on a pushed tag `v*`:

1. Checks out the code on a GitHub-hosted **macOS** runner (Swift 6 comes with the preinstalled Xcode).
2. Runs `scripts/test.sh`.
3. Decodes the `.p12` from a secret into a **temporary keychain** in `$RUNNER_TEMP` (GitHub's documented pattern), builds and signs.
4. Writes the `.p8` from a secret to `$RUNNER_TEMP`, notarizes with `notarytool --key/--key-id/--issuer --wait`, staples.
5. Uploads zip (+ DMG) and SHA-256 checksums to a **draft** GitHub Release, for you to review and publish by hand.

Repository secrets it expects (Settings → Secrets and variables → Actions):

| Secret | Contents |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | `base64 -i DeveloperID.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | password of that `.p12` |
| `DEVELOPER_ID_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `KEYCHAIN_PASSWORD` | any random string (for the throwaway CI keychain) |
| `ASC_API_KEY_P8_BASE64` | `base64 -i AuthKey_KEYID.p8 \| pbcopy` |
| `ASC_API_KEY_ID` | Key ID |
| `ASC_API_ISSUER_ID` | Issuer ID |

Hygiene:

- Put these secrets in a GitHub **Environment** (e.g. `release`) with a required reviewer, so a PR from a fork can never reach them.
- Pin third-party actions to a commit SHA.
- macOS runner minutes are free on **public** repos. On private repos they count 10× against your Actions minutes, so keep the repo private until you're ready, and don't run the release job there more than needed.

## 4. Homebrew

- **Official `homebrew/cask`:** since Homebrew 5 (Nov 2025) casks must pass Gatekeeper (signed + notarized), and unsigned casks were scheduled for removal by September 2026. The `--no-quarantine` flag is deprecated. Notability requirements also apply to new casks, so a brand-new personal app is unlikely to be accepted at first anyway.
- **Own tap first:** create a public repo `FelixSBuehrm/homebrew-tap` with `Casks/notch-mail.rb`:

  ```ruby
  cask "notch-mail" do
    version "1.0.0"
    sha256 "…"   # shasum -a 256 NotchMail-1.0.0.zip

    url "https://github.com/FelixSBuehrm/notch-mail/releases/download/v#{version}/NotchMail-#{version}.zip"
    name "Notch Mail"
    desc "New mail slides out of your MacBook notch"
    homepage "https://github.com/FelixSBuehrm/notch-mail"

    depends_on macos: ">= :sequoia"

    app "NotchMail.app"

    zap trash: [
      "~/Library/Preferences/io.github.felixsbuehrm.notchmail.plist",
    ]
  end
  ```

  Users then run `brew install --cask felixsbuehrm/tap/notch-mail`. The release workflow can bump `version` and `sha256` in the tap automatically later.

## 5. Sparkle (optional, later)

[Sparkle 2](https://sparkle-project.org/) is the standard for in-app updates outside the App Store: an appcast XML (can live on GitHub Pages or in the release assets), EdDSA-signed updates (`generate_keys` once; the private key becomes a CI secret, the public key goes into `Info.plist` as `SUPublicEDKey`).

Caveats for this project: Sparkle ships as a framework with XPC services, so with a plain SwiftPM build you'd copy `Sparkle.framework` into `Contents/Frameworks`, add an rpath, and sign it inside-out before the app. It's doable, but it's the most fiddly step here. Until then, a "new version available" check against the GitHub Releases API, or just Homebrew (`brew upgrade`), is enough.

## What happens without signing

If you share an unsigned (or self-signed / ad-hoc signed) build:

- **macOS 15 Sequoia and later:** first launch shows a dialog that the app "can't be opened" / "Apple could not verify…". The old **Control-click → Open** bypass **no longer works** for unsigned apps since Sequoia. Users have to:
  1. try to open the app once,
  2. go to **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to the Notch Mail message, and confirm with an admin password,
  3. open it again and confirm once more.
- **Terminal alternative** (for people who know what it means): remove the quarantine attribute after downloading:
  ```sh
  xattr -dr com.apple.quarantine /Applications/NotchMail.app
  ```
- **Keychain prompts** come back after every update unless every build is signed with the same identity.
- Some companies block apps that aren't notarized through MDM, so people on managed Macs may not be able to run it at all.

Fine for a couple of tech-savvy friends who build from source anyway. Not something to send around the office.

## Sources

- Apple Developer Program, membership fee: <https://developer.apple.com/programs/>
- Developer ID and notarization overview: <https://developer.apple.com/developer-id/>
- Notarizing outside Xcode / `notarytool`: <https://developer.apple.com/documentation/security/customizing-the-notarization-workflow>
- GitHub: installing an Apple certificate on macOS runners: <https://docs.github.com/en/actions/use-cases-and-examples/deploying/installing-an-apple-certificate-on-macos-runners-for-xcode-development>
- Sequoia Gatekeeper change (no more Control-click override): <https://9to5mac.com/2024/08/13/security-bite-apple-finally-making-it-harder-to-override-gatekeeper-is-a-telling-move/>, <https://troz.net/post/2024/sequoia_app_permissions/>
- Homebrew 5.0.0 (Gatekeeper requirement for casks, `--no-quarantine` deprecation): <https://brew.sh/blog/> and <https://workbrew.com/blog/homebrew-5-0-0>
- Sparkle: <https://sparkle-project.org/documentation/>
