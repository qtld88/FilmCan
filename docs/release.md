# Releasing FilmCan

`FilmCan/scripts/package_release.sh` builds both architectures, lipos them into one
universal binary, signs the bundle, and produces `FilmCan/dist/FilmCan.dmg`.

```bash
bash FilmCan/scripts/package_release.sh
```

The script is self-contained: no Apple credentials, no network. It takes several minutes
because it builds Release twice, once per architecture.

## Code signing

FilmCan is **not notarized** and has no paid Developer ID. Anyone downloading the DMG has
to right-click → Open the first time to get past Gatekeeper. That is unchanged and is not
what the signing certificate below is for.

### The saved ntfy token disappears on update — root cause

`KeychainStore` writes the ntfy bearer token to the login keychain as a generic password.
The app is not sandboxed, so the item lands in the **file-based** keychain and is guarded
by a **partition list**. Dumping the access control of an item FilmCan created:

```
ACL[0] trustedApps = nil (= any application)          <- not the gate
ACL[3] Partitions  = [ cdhash:0516 6a83… ]            <- the gate
```

The trusted-application list is already wide open. What refuses a new build is the
partition list, pinned to the binary's **cdhash**, which changes with every build.

Scanning every generic-password item on a real machine (metadata only, no secrets read):

| partition kind | items |
|---|---|
| `teamid:` | 76 |
| `cdhash:` | 31 |

Every normally-signed app — Nextcloud, Bitwarden, Signal, VS Code — gets `teamid:<TeamID>`,
one value for the whole developer account, stable across every build and every certificate
renewal. FilmCan gets cdhash, and accumulates one entry per version the user has ever
approved:

```
com.filmcan.app -> cdhash:26dffd13…, cdhash:1d870fde…, cdhash:7e2e6cdb…, cdhash:1067ed77…
```

Four entries means four "Always Allow" clicks. So the real symptom is **a prompt on every
update**, not silent data loss.

macOS writes `teamid:` only when the signing chain is **anchored to Apple** and the leaf
certificate carries a team OU.

### What does not fix it

A self-signed certificate does **not**, and this was measured rather than assumed. Two
Swift binaries, identical apart from a marker string so their cdhashes differ, same
signing identifier, run as real `.app` bundles; A writes a generic password, B reads it,
with `SecKeychainSetUserInteractionAllowed(false)` turning the GUI prompt into a status
code:

| attempt | result |
|---|---|
| ad-hoc signed (control) | `-25293` errSecAuthFailed — reproduces the bug |
| A reads back its own item (sanity) | `0` |
| self-signed certificate, bare binaries | `-25293` |
| self-signed certificate, `.app` bundles | `-25293` |
| `kSecUseDataProtectionKeychain: true` | `-34018` errSecMissingEntitlement — needs a team |
| `SecAccessCreate(_, [] as CFArray, _)` | `-25293` — an empty array means *nobody* |
| `SecACLSetContents(acl, nil, …)` | `-25293` — the ACL was never the gate |

A self-signed root is not Apple-anchored, so the partition stays cdhash-keyed no matter
how stable the designated requirement looks.

Worth remembering, because it cost two attempts: in `SecAccessCreate` a nil
trusted-application list means *the creating application only*, while in
`SecACLSetContents` nil means *any application*.

### What might fix it, untested

A **free Apple Development certificate** (free Apple ID, no paid membership) is
Apple-anchored and carries the Team ID in its OU, so it should produce a `teamid:`
partition — stable across builds and across annual certificate renewal, because the Team
ID belongs to the account rather than the certificate. That is a hypothesis with a
mechanism, not a result. Run the A/B probe above before believing it.

The alternatives that need no signing at all both downgrade the token to "any process
running as this user can read it", which for an ntfy bearer token may be an acceptable and
explicit trade: a `0600` file in Application Support, or simply keeping today's behaviour
of one approval click per update.

### What the certificate does buy

A stable designated requirement, verified by signing two copies of the same app with
different cdhashes:

| | cdhash | designated requirement |
|---|---|---|
| A | `ede30cef…` | `identifier "com.filmcan.app" and certificate root = H"8cfd4384…"` |
| B | `ac7799f8…` | `identifier "com.filmcan.app" and certificate root = H"8cfd4384…"` |

That is real and reproducible. It is simply not what the keychain checks.

### Creating the certificate

One-time, on the release machine only.

1. Keychain Access → menu **Keychain Access ▸ Certificate Assistant ▸ Create a
   Certificate…**
2. Name `FilmCan Release`, identity type **Self Signed Root**, certificate type **Code
   Signing**.
3. Tick **Let me override defaults** — the only reason to override is the validity
   period. The default is 365 days, after which releases would start failing.
4. Validity **3650** days. Key size 2048, algorithm RSA. Leave every extension screen at
   its defaults; **Code Signing** must be the extended key usage.
5. Store it in the **login** keychain.

Confirm it exists:

```bash
security find-identity -p codesigning
```

`security find-identity -v` (valid identities only) will **not** list it. A self-signed
root reports `CSSMERR_TP_NOT_TRUSTED` because it is not in the system trust store, which
is why the script matches against the unfiltered list. `codesign` accepts the identity
regardless, so this does not block signing. Adding a local trust override would not help:
end users will never have this certificate in their trust store, so anything that depends
on trust cannot ship.

### How the script picks the identity

The certificate is resolved by name, so no machine-specific hash lives in the repo:

- Default name `FilmCan Release`; override with `FILMCAN_SIGN_IDENTITY_NAME`.
- `FILMCAN_SIGN_IDENTITY` bypasses the lookup entirely. Set it to `-` to force ad-hoc.
- **No certificate found → the build still succeeds, signed ad-hoc**, with a warning. A
  contributor building from a fresh checkout is never blocked.

After signing, the script asserts the resulting requirement is identity-based and **fails
the build** if it ever comes back cdhash-based, so a signing change cannot quietly revert
to ad-hoc.

`project.yml` deliberately keeps `CODE_SIGN_IDENTITY: "-"`. Xcode's build-time signature
is replaced wholesale by the script's final `codesign --force --deep`, so changing it
would have no effect on the shipped DMG while breaking `xcodebuild` for anyone without
the certificate.

Contributors who build from source sign with their own certificate or ad-hoc, so their
requirement differs from the published builds. Nothing here changes that.

## Release checklist

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `FilmCan/project.yml`.
2. `cd FilmCan && xcodegen generate` — never hand-edit `project.pbxproj`.
3. Commit, push `main`.
4. Tag `Release_X.Y.Z` (underscores), push the tag.
5. `bash FilmCan/scripts/package_release.sh` — check it prints `Signing identity:` and an
   `identifier … certificate root` requirement, not a warning.
6. Smoke-test the built app on a real volume before publishing. Automated tests do not
   catch runtime, UI, or volume bugs; see `docs/smoke-qa-checklist.md`.
7. `gh release create Release_X.Y.Z FilmCan/dist/FilmCan.dmg --title … --notes …`
