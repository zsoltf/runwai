# macOS signing and notarization

This is the shortest path to a clean public `runwai` build.

For distribution outside the Mac App Store, Apple currently expects:

- `Developer ID Application` signing
- hardened runtime enabled
- notarization
- stapling

Repo helper:

- `scripts/release_macos.sh`

## done looks like this

These commands succeed:

```bash
security find-identity -v -p codesigning
APPLE_TEAM_ID=YOURTEAMID APPLE_NOTARY_PROFILE=runwai-notary ./scripts/release_macos.sh --preflight
APPLE_TEAM_ID=YOURTEAMID APPLE_NOTARY_PROFILE=runwai-notary ./scripts/release_macos.sh
```

And the exported app passes:

```bash
codesign --verify --deep --strict --verbose=2 build/release/export/runwai.app
spctl --assess --type execute --verbose=4 build/release/export/runwai.app
```

## 1. apple account setup

You need:

1. an Apple Developer Program membership
2. a `Developer ID Application` certificate installed on this Mac
3. a notary profile saved in the local keychain

Current Apple references:

- [Developer ID](https://developer.apple.com/support/developer-id/)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

## 2. create or install the certificate

In Xcode:

1. open `Xcode -> Settings -> Accounts`
2. sign into the Apple account that owns the developer team
3. select the team
4. click `Manage Certificates`
5. create or import `Developer ID Application`

Then verify in Terminal:

```bash
security find-identity -v -p codesigning
```

You should see a line containing `Developer ID Application`.

## 3. store notary credentials

Run:

```bash
xcrun notarytool store-credentials "runwai-notary"
```

Use the team that owns the certificate. After that, sanity-check it:

```bash
xcrun notarytool history --keychain-profile runwai-notary
```

## 4. preflight this repo

From this repo:

```bash
cd /path/to/runwai
APPLE_TEAM_ID=YOURTEAMID \
APPLE_NOTARY_PROFILE=runwai-notary \
./scripts/release_macos.sh --preflight
```

This checks:

- required tools
- `Developer ID Application` identity
- team id
- notary profile

If this fails, stop there and fix the missing prerequisite first.

## 5. build the signed release

Once preflight passes:

```bash
cd /path/to/runwai
APPLE_TEAM_ID=YOURTEAMID \
APPLE_NOTARY_PROFILE=runwai-notary \
./scripts/release_macos.sh
```

The script will:

1. regenerate the Xcode project
2. archive `Runwai`
3. export a Developer ID build
4. submit it for notarization
5. staple the ticket
6. verify the result
7. zip the app

Output:

- `build/release/dist/runwai-macos.zip`

## 6. optional api key auth

If you do not want to rely on the Xcode account on the machine, the script also supports:

```bash
APP_STORE_CONNECT_KEY_PATH=/absolute/path/AuthKey_ABC123XYZ.p8
APP_STORE_CONNECT_KEY_ID=ABC123XYZ
APP_STORE_CONNECT_ISSUER_ID=00000000-0000-0000-0000-000000000000
```

Pass those together with `APPLE_TEAM_ID` and `APPLE_NOTARY_PROFILE`.

## 7. current blocker on this mac

Right now this Mac is not release-ready yet.

Last verified state:

- `security find-identity -v -p codesigning` returned `0 valid identities found`
- the notary profile was not usable yet

So the next real step is still:

1. install `Developer ID Application`
2. store `runwai-notary`
3. rerun preflight
