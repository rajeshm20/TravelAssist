# CI/CD setup (Fastlane + GitHub Actions)

## Required GitHub Secrets

- `ASC_KEY_ID`: App Store Connect API Key ID
- `ASC_ISSUER_ID`: App Store Connect Issuer ID
- `ASC_KEY_CONTENT_BASE64`: Base64 of the `.p8` API key file contents
- `FASTLANE_TEAM_ID`: Apple Developer Team ID
- `FASTLANE_APPLE_ID`: Apple ID email (optional; useful for some fastlane actions)

### Code signing (recommended: match)

- `MATCH_GIT_URL`: Git URL to the private certificates repo
- `MATCH_PASSWORD`: Password used to encrypt match repository
- `MATCH_GIT_BASIC_AUTHORIZATION`: Base64 `username:token` (optional; if your match repo needs auth)

## Do not commit secrets

- Keep App Store Connect `.p8` keys, provisioning profiles, certificates, and any `.env` files out of git.
- This repo’s `.gitignore` already ignores common secret/signing artifacts, but you should still enable GitHub secret scanning in the repo settings.

## Workflows

- `.github/workflows/ci.yml`: Runs unit tests on pull requests and pushes to `main`.
- `.github/workflows/release.yml`:
  - Manual: `workflow_dispatch` with lane `beta` or `release`
  - Automatic: tag push matching `v*` runs `beta` lane by default (edit if you prefer release-on-tag)
