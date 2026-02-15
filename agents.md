# HaraUI — CI / Publishing Reference

## Release Pipeline (GitHub Actions)

When you push a git tag matching `v*`, the workflow at `.github/workflows/release.yml` runs automatically:

1. **Package** — BigWigsMods/packager builds a distributable `.zip` from the repo, guided by `.pkgmeta`. The `@project-version@` token in `HarathUI/HarathUI.toc` is replaced with the tag name (e.g. `v2.0.3`).
2. **GitHub Release** — A release is created for the tag with auto-generated notes and the zip attached.
3. **CurseForge Upload** — The same zip is uploaded to CurseForge with the correct release type.

### Tag → Release Type Mapping

| Tag pattern            | Release type | Example           |
|------------------------|--------------|-------------------|
| `v2.0.3`               | `release`    | Stable release    |
| `v2.0.3-beta.1`        | `beta`       | Beta / pre-release|
| `v2.0.3-alpha.1`       | `alpha`      | Alpha / dev build |

---

## How to Release

### 1. Ensure main branch is clean

```bash
git checkout main
git pull
git status  # should be clean
```

### 2. Create a tag

**Stable release:**
```bash
git tag v2.0.3
```

**Beta:**
```bash
git tag v2.0.3-beta.1
```

**Alpha:**
```bash
git tag v2.0.3-alpha.1
```

### 3. Push the tag

```bash
git push origin v2.0.3
```

Or push all tags at once:
```bash
git push origin --tags
```

### 4. Monitor

- Go to **Actions** tab in GitHub — the "Release" workflow should be running.
- Once complete, check:
  - GitHub Releases page for the new release + zip download
  - CurseForge project page for the new file

---

## Required GitHub Secrets

| Secret name              | Where to get it                                                                 |
|--------------------------|---------------------------------------------------------------------------------|
| `CURSEFORGE_API_TOKEN`   | [CurseForge API Tokens](https://authors.curseforge.com/account/api-tokens) — generate a token with upload permissions |

### Required Workflow Config

In `.github/workflows/release.yml`, set the `CURSEFORGE_PROJECT_ID` env var to your CurseForge project's numeric ID. You can find this on your project's sidebar on the CurseForge author dashboard.

```yaml
env:
  CURSEFORGE_PROJECT_ID: "123456"  # replace with actual ID
```

---

## How to Roll Back a Bad Release

### Delete the tag and re-tag

```bash
# Delete remote tag
git push origin --delete v2.0.3

# Delete local tag
git tag -d v2.0.3

# Fix the issue, commit, then re-tag
git tag v2.0.4
git push origin v2.0.4
```

### Delete a GitHub Release

Go to the GitHub Releases page → find the release → click **Delete**.

### Remove from CurseForge

Log into the CurseForge author dashboard → navigate to the file → delete it manually. CurseForge does not support API-based file deletion.

---

## Version Stamping

- **Source of truth:** The git tag. No version is hardcoded in the source tree.
- **Mechanism:** `HarathUI/HarathUI.toc` contains `## Version: @project-version@`. The BigWigsMods packager replaces this token with the tag name at build time.
- **Local development:** When running the addon directly from the repo (not packaged), the version line reads literally `@project-version@`. This is normal — WoW treats it as a string. The in-addon version tracker (`Core/VersionTracker.lua`) handles version comparison separately.

---

## File Reference

| File                              | Purpose                                           |
|-----------------------------------|---------------------------------------------------|
| `.pkgmeta`                        | Packager config: folder mapping, ignore rules     |
| `.github/workflows/release.yml`   | Tag-triggered CI: package → release → upload      |
| `HarathUI/HarathUI.toc`          | Addon manifest (contains `@project-version@` token)|
| `scripts/release-harathui.ps1`    | Legacy local release script (pre-CI)              |
