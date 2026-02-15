# HaraUI - CI / Publishing Reference

## Workflow Triggers

- `.github/workflows/ci.yml` runs on `push` to branches and on `pull_request`.
- `.github/workflows/ci.yml` is validation-only and never publishes artifacts.
- `.github/workflows/release.yml` runs only on `push` tags matching `v*`.
- Only `.github/workflows/release.yml` can package, create a GitHub Release, and upload to CurseForge.

## Release Pipeline (Tags Only)

When you push a tag that matches `v*`, `.github/workflows/release.yml` executes:

1. Parse tag metadata and map tag to release type (`release`, `beta`, `alpha`).
2. Package with `BigWigsMods/packager@v2` using `.pkgmeta`.
3. Stamp version from tag into the packaged TOC:
   - Source file keeps `## Version: @project-version@` in `HaraUI/HaraUI.toc`.
   - Packager replaces `@project-version@` with the pushed tag value in the release zip.
4. Generate release notes from commit subjects in the current tag range:
   - Range is `previous_tag..current_tag` (or start of history for the first tag).
   - Notes are grouped into `Added`, `Changed`, and `Fixed` bullets.
   - The same generated notes body is used for both GitHub Release and CurseForge.
5. Create GitHub Release for the tag and attach the generated zip.
6. Upload the same zip to CurseForge with the same release notes.

### Tag -> Release Type Mapping

| Tag pattern            | Release type | Example           |
|------------------------|--------------|-------------------|
| `v2.0.3`               | `release`    | Stable release    |
| `v2.0.3-beta.1`        | `beta`       | Beta pre-release  |
| `v2.0.3-alpha.1`       | `alpha`      | Alpha dev build   |

## Safe Push Behavior

- Normal branch pushes (no tag) run `CI` only.
- Normal branch pushes do not create a GitHub Release.
- Normal branch pushes do not upload to CurseForge.

## How to Release

1. Ensure your branch is ready:

```bash
git checkout main
git pull
git status
```

2. Create a tag:

```bash
# Stable
git tag v2.0.3

# Beta
git tag v2.0.3-beta.1

# Alpha
git tag v2.0.3-alpha.1
```

3. Push the tag:

```bash
git push origin v2.0.3
```

## Required GitHub Secrets and Config

| Name                     | Purpose |
|--------------------------|---------|
| `CURSEFORGE_API_TOKEN`   | Required by `itsmeow/curseforge-upload@v3` |

`CURSEFORGE_PROJECT_ID` is set in `.github/workflows/release.yml` and must match the CurseForge project numeric ID.

## Version Stamping

- Source of truth is the git tag used for release.
- `HaraUI/HaraUI.toc` intentionally stores `## Version: @project-version@` in source control.
- The packaged artifact gets the concrete tag value during the release workflow.

## Legacy Script Status

- `scripts/release-haraui.ps1` was removed.
- It was not used by CI and referenced a missing `stamp-version-metadata.ps1` script.
- Use GitHub Actions tag releases as the single publishing path.

## File Reference

| File                            | Purpose |
|---------------------------------|---------|
| `.github/workflows/ci.yml`      | Branch/PR validation only (safe push path) |
| `.github/workflows/release.yml` | Tag-triggered package + GitHub Release + CurseForge upload |
| `.pkgmeta`                      | Packager layout and ignore rules |
| `HaraUI/HaraUI.toc`             | TOC manifest with `@project-version@` token |
