# Security Policy

## Supported Versions

TravelAssist is currently under active development.

| Version | Supported |
| ------- | --------- |
| main    | ✅ |
| older commits/releases | ❌ |

---

## Reporting a Vulnerability

If you discover a security vulnerability in TravelAssist, please report it responsibly.

### Please include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Screenshots or logs if applicable
- Suggested fix (optional)

---

## Reporting Method

Please do **not** open public GitHub issues for security vulnerabilities.

Instead, contact:

- GitHub Security Advisory (preferred)
- Email: `YOUR_EMAIL_HERE`

If you do not want to publish your email, you can rely entirely on GitHub private vulnerability reporting.

---

## Response Timeline

I will try to:

- Acknowledge reports within **7 days**
- Investigate and validate the issue
- Release a fix as soon as reasonably possible
- Credit the reporter where appropriate

---

## Scope

This policy applies to:

- iOS application source code
- GitHub Actions workflows
- Dependency configuration
- Local data storage
- Route/location processing features
- GPX export/import functionality

---

## Security Best Practices

TravelAssist aims to follow secure development practices including:

- No hardcoded secrets or API keys
- Principle of least privilege
- Secure handling of location data
- Minimal data retention
- Dependency updates and monitoring
- Safe GitHub Actions workflow permissions

---

## Sensitive Data

Please avoid including:

- Personal location history
- GPX files containing private routes
- API tokens
- Apple Developer credentials
- Provisioning profiles
- `.env` files
- Authentication secrets

in public discussions or reports.

---

## Third-Party Services

TravelAssist may use Apple frameworks and services including:

- MapKit
- CoreLocation
- WeatherKit
- Cloud-based Apple APIs

Security issues affecting those services should also be reported to Apple where appropriate.

---

## Disclosure Policy

Please allow reasonable time for vulnerabilities to be fixed before public disclosure.

Responsible disclosure helps protect all users of the project.

---

## Thanks

Thank you for helping improve the security and reliability of TravelAssist.
