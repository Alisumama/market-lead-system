# Releasing & auto-updates (Windows)

The Windows app self-updates. Each client, on launch (and via **Settings → Updates
→ Check for updates**), reads a version manifest from Firestore over its REST API,
compares it to the running version, and — if a newer build exists — downloads the
installer from GitHub Releases, verifies its SHA-256, and runs it silently. The
Inno Setup installer keeps a stable `AppId`, so it upgrades in place and relaunches.

```
launch ─► GET firestore REST config/appVersion ─► newer? ─► download setup.exe
        ─► verify sha256 ─► run /VERYSILENT ─► Inno upgrades in place & relaunches
```

Pieces:
- **Manifest**: Firestore `config/appVersion` document (public read; see `firestore.rules`).
- **Binary**: a GitHub Release asset on `Alisumama/market-lead-system`.
- **Client**: `lib/services/update_service.dart` + `lib/ui/updates/update_dialog.dart`.

## One-time setup

1. **Deploy the rules** (adds the public read on `config/`):
   ```
   firebase deploy --only firestore:rules
   ```
2. **Create the manifest doc** in the Firebase console → Firestore → collection
   `config`, document id `appVersion`, fields:

   | field       | type    | example                                   |
   |-------------|---------|-------------------------------------------|
   | `version`   | string  | `2.1.4`                                    |
   | `url`       | string  | GitHub asset URL (filled in per release)  |
   | `sha256`    | string  | installer hash (filled in per release)    |
   | `mandatory` | boolean | `false`                                   |
   | `notes`     | string  | what's new                                |

   Writes are denied by the rules, so edit this doc from the **console** (it
   bypasses rules). Set `version` to the *current* shipped version to start.
3. **Code signing (strongly recommended).** Unsigned installers trip SmartScreen
   on every update. Configure one of:
   - a cert in your user store: `setx BASTAK_SIGN_THUMBPRINT <sha1-thumbprint>`
   - or a PFX: `setx BASTAK_SIGN_PFX C:\path\cert.pfx` + `setx BASTAK_SIGN_PFX_PASSWORD ****`

   The build script signs the exe and installer automatically when set, and warns
   (but still builds) when not. Azure Trusted Signing is a good cert-less option.

## Cutting a release — automated (recommended)

The `.github/workflows/release-windows.yml` workflow does everything on a tag push:
build → sign → create the GitHub release + upload the installer → point the
Firestore manifest at it.

```
# bump pubspec.yaml first (e.g. version: 2.1.5+10), commit, then:
git tag -a v2.1.5 -m "What's new in this release"   # tag message = release notes
git push origin v2.1.5
```

The tag **must** match `pubspec.yaml` (`v2.1.5` ⇄ `version: 2.1.5+…`) or the job
fails fast. The annotated tag message becomes both the GitHub release notes and
the in-app update notes.

### Repo secrets the workflow uses

| secret                       | required? | purpose                                                    |
|------------------------------|-----------|------------------------------------------------------------|
| `FIREBASE_SERVICE_ACCOUNT`   | for auto-manifest | JSON key of a service account with `roles/datastore.user`; used to PATCH `config/appVersion`. Bypasses security rules (server credential). |
| `BASTAK_SIGN_PFX_BASE64`     | recommended | base64 of your code-signing `.pfx` (`certutil -encode` / `base64`). |
| `BASTAK_SIGN_PFX_PASSWORD`   | with the above | its password.                                         |

`GITHUB_TOKEN` (release + asset upload) is provided automatically.

Both signing and the Firestore publish are **optional**: if a secret is absent
the job still builds and releases, and warns. Without `FIREBASE_SERVICE_ACCOUNT`
you'd finish by editing `config/appVersion` by hand (below).

## Cutting a release — manual

1. Bump `version:` in `pubspec.yaml` (e.g. `2.1.5+10`).
2. Build + sign the installer:
   ```
   powershell -ExecutionPolicy Bypass -File tool\build_windows_installer.ps1
   ```
   It prints the **SHA-256** and the exact **asset URL** to use.
3. On GitHub, create a release tagged **`v<version>`** (e.g. `v2.1.5`) and upload
   `bastak_leads-<version>-windows-x64-setup.exe` as an asset. The tag + asset
   name must match the printed URL:
   ```
   https://github.com/Alisumama/market-lead-system/releases/download/v2.1.5/bastak_leads-2.1.5-windows-x64-setup.exe
   ```
4. In the Firebase console, update `config/appVersion`: set `version`, `url`,
   `sha256` (from step 2), `notes`, and `mandatory` as needed.
5. Done — running clients pick it up on their next launch or manual check.

## Notes & gotchas

- **Per-user vs per-machine.** The installer defaults to per-user
  (`%LOCALAPPDATA%\Programs`), which updates with **no UAC prompt**. All-users
  installs (elevated) will prompt for elevation on each update.
- **Rollback.** Point `config/appVersion` back at the previous `version`/`url`/
  `sha256`. Clients only ever move to a *strictly higher* version, so lowering the
  manifest stops further upgrades but won't downgrade already-updated clients.
- **Staged rollout / force update.** Flip `mandatory: true` to make the prompt
  non-dismissible.
- **macOS/Android** ignore this system (`UpdateService.supported` is Windows-only);
  distribute those through their normal channels.
- **Version compare** uses numeric `major.minor.patch` from `pubspec.yaml`
  (the `+build` suffix is ignored).
