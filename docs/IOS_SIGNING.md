# iOS code signing — setup guide

The signed iOS pipeline lives in
[`.github/workflows/ios-release.yml`](../.github/workflows/ios-release.yml) and runs
**only on `v*` tag pushes** (or manual `workflow_dispatch`). Regular pushes/PRs
keep producing unsigned builds via `ios.yml`.

The workflow expects a small set of GitHub Secrets. Set them up once, push a
tag, get a signed IPA artifact you can sideload via Xcode or Apple Configurator.

> **Never paste certificates, profiles, passwords, or API keys into chat or
> commit them.** Always go directly to GitHub → Settings → Secrets and variables
> → Actions.

---

## Apple Developer Portal — one-time setup

You need an active Apple Developer Program membership ($99/year).

### 1. Register the App ID

Apple Developer → **Identifiers** → **+** → App IDs → App.

- Description: `Inscription Raking Light`
- Bundle ID (explicit): `com.paxetheninja.inscriptionRakingLight`
- Capabilities: leave default for now

### 2. Register your iPhone (or iPad) UDID

Ad-hoc distribution embeds a list of device UDIDs in the provisioning profile —
only listed devices can install the resulting IPA.

To find a device UDID:
- Connect the device to a Mac via cable.
- Open Finder → click the device in the sidebar → click the line under the
  device name (it cycles through capacity / battery / serial / UDID). Copy
  the long hex string.

Apple Developer → **Devices** → **+** → name + UDID. Repeat for every device
you want to install on.

### 3. Create the distribution certificate

Apple Developer → **Certificates** → **+** → **Apple Distribution**.

- On a Mac, open *Keychain Access* → Certificate Assistant → *Request a
  Certificate From a Certificate Authority…* → save the `.certSigningRequest`
  file. Upload it on the certificate-creation page.
- Download the resulting `.cer` and double-click to install it into your login
  keychain.
- In Keychain Access, find the cert, expand it to see the linked private key,
  right-click the cert → **Export…** → choose `.p12`, set a password (you'll
  use this in GitHub later). **Important:** the export must include the
  private key — that's why we export the cert+key pair, not the cert alone.

### 4. Create the provisioning profile

Apple Developer → **Profiles** → **+** → **Ad Hoc** (under "Distribution").

- App ID: pick the one you just created.
- Certificates: pick your Apple Distribution cert.
- Devices: tick every device you registered.
- Name: e.g. `Inscription RL — Ad Hoc`.
- Download the `.mobileprovision` file.

### 5. Note your Team ID

Apple Developer → **Membership** → look for "Team ID" (10-character
alphanumeric, e.g. `AB12CD34EF`).

---

## GitHub Secrets — names and contents

Go to `https://github.com/paxetheninja/inscription-raking-light/settings/secrets/actions`
and add each of these as a **Repository secret**:

| Secret | What goes in it |
| --- | --- |
| `IOS_DIST_CERT_P12` | The `.p12` file from step 3, **base64-encoded**. See command below. |
| `IOS_DIST_CERT_PASSWORD` | The password you set when exporting the `.p12`. |
| `IOS_PROVISIONING_PROFILE` | The `.mobileprovision` from step 4, **base64-encoded**. |
| `IOS_TEAM_ID` | Your 10-character Team ID from step 5. |

### Encoding the files

On macOS / Linux:

```sh
base64 -i dist.p12 -o dist.p12.b64           # paste the contents into IOS_DIST_CERT_P12
base64 -i profile.mobileprovision -o profile.b64
```

On Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("dist.p12")) | Set-Clipboard
# paste into the GitHub secret field; repeat for the .mobileprovision
```

---

## Producing a signed IPA

```sh
git tag v0.4
git push origin v0.4
```

That triggers the `iOS Release (signed)` workflow. When it finishes, the run
page has an artifact named `inscription-raking-light-v0.4-ipa` containing
the IPA.

To install it on a registered device:

1. Download and unzip the artifact.
2. Open Xcode → Window → Devices and Simulators → select your device → drag
   the IPA onto "Installed Apps".
3. Or use Apple Configurator 2: drag the IPA onto the device tile.

If you get **"This device is not registered in the provisioning profile"**,
either the device's UDID isn't in the profile (re-do step 2 above, regenerate
the profile, re-export, re-encode, re-set the secret) or you used a different
device than the one you registered.

---

## Local Xcode signing still works

The workflow writes `ios/Flutter/Signing.xcconfig` only on the CI runner —
that file is `.gitignore`d. When you open the project locally, Xcode falls
back to **Automatic** signing using whatever team is selected in the Signing
& Capabilities tab. No interference between local dev and CI.

---

## Future: TestFlight upload

When you're ready to ship internally via TestFlight, four extra secrets get
the workflow there:

- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_BASE64` (the `.p8` private key, base64-encoded)
- Change `method` in `ExportOptions.plist` from `ad-hoc` to `app-store`.

Then add a final step to the workflow:

```yaml
- name: Upload to TestFlight
  env:
    KEY_ID: ${{ secrets.APP_STORE_CONNECT_API_KEY_ID }}
    ISSUER_ID: ${{ secrets.APP_STORE_CONNECT_API_ISSUER_ID }}
    KEY_B64: ${{ secrets.APP_STORE_CONNECT_API_KEY_BASE64 }}
  run: |
    mkdir -p ~/.appstoreconnect/private_keys
    echo "$KEY_B64" | base64 --decode > "~/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8"
    xcrun altool --upload-app -f build/ios/ipa/*.ipa --type ios \
      --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"
```

Ask later and I'll wire it up — but it's not needed for v1.
