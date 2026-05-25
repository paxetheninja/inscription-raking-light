# iOS code signing & TestFlight distribution

The signed iOS pipeline lives in
[`.github/workflows/ios-release.yml`](../.github/workflows/ios-release.yml) and
runs **only on `v*` tag pushes** (or manual `workflow_dispatch`). Regular
pushes/PRs keep producing unsigned builds via `ios.yml` as a smoke test.

On a `v*` tag, the workflow:
1. Decodes the distribution certificate and provisioning profile from Secrets.
2. Builds a signed App Store IPA via `flutter build ipa`.
3. Uploads the IPA to App Store Connect via `xcrun altool`.
4. The build appears in TestFlight a few minutes later — internal testers get
   it instantly, external testers after a one-time Apple beta review.
5. The IPA is also attached as a workflow artifact (for safekeeping / manual
   ad-hoc installs).

You set up GitHub Secrets and the App Store Connect record once, then push a
tag whenever you want testers to get a new build.

> **Never paste certificates, profiles, passwords, or API keys into chat or
> commit them.** Always go directly to GitHub → Settings → Secrets and
> variables → Actions.

---

## Apple Developer Portal — one-time setup

You need an active Apple Developer Program membership ($99/year).

### 1. Register the App ID

Apple Developer → **Identifiers** → **+** → App IDs → App.

- Description: `Stela`
- Bundle ID (explicit): `com.paxetheninja.inscriptionRakingLight`
- Capabilities: leave default for now.

### 2. Create the distribution certificate

Apple Developer → **Certificates** → **+** → **Apple Distribution**.

- On a Mac, open *Keychain Access* → Certificate Assistant → *Request a
  Certificate From a Certificate Authority…* → save the `.certSigningRequest`
  file. Upload it on the certificate-creation page.
- Download the resulting `.cer` and double-click to install into your login
  keychain.
- In Keychain Access, find the cert, expand it to see the linked private
  key, right-click the cert → **Export…** → choose `.p12`, set a password
  (you'll use this in GitHub as `IOS_DIST_CERT_PASSWORD`). The export must
  include the private key.

### 3. Create an **App Store** provisioning profile

Apple Developer → **Profiles** → **+** → **App Store** (under "Distribution").

- App ID: the one you created above.
- Certificates: pick your Apple Distribution cert.
- Name: e.g. `Stela — App Store`.
- Download the `.mobileprovision` file.

Notice this is **App Store**, not Ad Hoc — no device UDIDs needed.

### 4. Note your Team ID

Apple Developer → **Membership** → look for "Team ID" (10-character
alphanumeric, e.g. `AB12CD34EF`).

---

## App Store Connect — one-time setup

### 5. Create the App record

App Store Connect → **My Apps** → **+** → New App.

- Platform: iOS
- Name: `Stela`
- Primary language: English (or German, your call)
- Bundle ID: `com.paxetheninja.inscriptionRakingLight`
- SKU: anything stable (e.g. `stela-001`) — internal identifier
- User access: Full Access

You do **not** need to fill in App Store metadata (screenshots, description,
etc.) just to ship to TestFlight. The app record exists, that's enough.

### 6. Generate an App Store Connect API key

App Store Connect → **Users and Access** → **Integrations** → **App Store
Connect API** → **+** to generate a new key.

- Name: `Stela CI Upload`
- Access: **App Manager** (sufficient for TestFlight uploads). Admin works too.
- **Download the `.p8` file when it's offered — Apple only shows it once.**
  Store it locally (e.g. `~/Documents/AuthKey_<KEY_ID>.p8`).
- Note the **Key ID** (shown on the row, ~10 chars) and the **Issuer ID**
  (shown at the top of the page, a UUID).

### 7. Add testers

App Store Connect → **TestFlight**.

- **Internal Testing** group: add users that have an Apple ID on your dev
  team. They get builds instantly, no review.
- **External Testing** group: add users by email. The first build to an
  external group needs a one-time Apple beta review (24–48 hours
  typically); subsequent builds are usually auto-approved.

---

## GitHub Secrets — names and contents

Go to
`https://github.com/paxetheninja/inscription-raking-light/settings/secrets/actions`
and add each of these as a **Repository secret**:

| Secret | What goes in it |
| --- | --- |
| `IOS_DIST_CERT_P12` | The `.p12` file from step 2, **base64-encoded**. |
| `IOS_DIST_CERT_PASSWORD` | The password you set when exporting the `.p12`. |
| `IOS_PROVISIONING_PROFILE` | The App Store `.mobileprovision` from step 3, **base64-encoded**. |
| `IOS_TEAM_ID` | Your 10-character Team ID from step 4. |
| `APP_STORE_CONNECT_API_KEY_ID` | The Key ID from step 6 (e.g. `AB12CD34EF`). |
| `APP_STORE_CONNECT_API_ISSUER_ID` | The Issuer ID UUID from step 6. |
| `APP_STORE_CONNECT_API_KEY_BASE64` | The `.p8` file from step 6, **base64-encoded**. |

### Encoding the files

On macOS / Linux:

```sh
base64 -i dist.p12 -o dist.p12.b64
base64 -i profile.mobileprovision -o profile.b64
base64 -i ~/Documents/AuthKey_AB12CD34EF.p8 -o auth_key.b64
```

On Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("dist.p12")) | Set-Clipboard
# paste into the GitHub secret field; repeat for the .mobileprovision and .p8
```

---

## Shipping a build to TestFlight

```sh
git tag v0.9.1
git push origin v0.9.1
```

That triggers the `iOS Release (TestFlight)` workflow. About 5–10 minutes
later the build appears in **App Store Connect → TestFlight → Builds**.
Apple's processing takes another 5–15 minutes — once it's "Ready to
Submit", internal testers get an email + a notification in the TestFlight
app and can install immediately.

External testers need the build to be added to an external testing group
and pass beta review the first time; thereafter it ships automatically.

## Inviting a tester

App Store Connect → TestFlight → either **Internal Testing** or **External
Testing** → **+** next to a group → enter email.

The user receives an email with a link. On their iPhone:
1. Install the free **TestFlight** app from the App Store.
2. Open the invite email on the phone, tap the link.
3. Tap **Install** in TestFlight.

That's it. No Mac, no UDID collection, no developer profile trust step.
Updates auto-pull whenever you push a new tag.

## Local Xcode signing still works

The workflow writes `ios/Flutter/Signing.xcconfig` only on the CI runner —
that file is `.gitignore`d. When you open the project locally, Xcode falls
back to **Automatic** signing using whatever team is selected in the
Signing & Capabilities tab. No interference between local dev and CI.

## When to push a new tag

- TestFlight builds **expire after 90 days**. If you haven't shipped a new
  version in three months, testers will see "This beta has expired" and
  can't install. Push any tag (e.g. `v0.9.2`) to refresh.
- Anytime you've made a meaningful improvement and want testers to see it.
- For each `v*` tag, bump `version:` in `pubspec.yaml` (the `+N` build
  number must be strictly greater than the previous TestFlight build — App
  Store Connect rejects duplicates).
