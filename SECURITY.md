# Security Notes

**Author:** ChatGPT 5.2 + GitHub Copilot
**Created:** 2026-01-14
**Updated:** 2026-06-16

## Implemented Mitigations (P0 / P1)

As of 2026-06-16, the following mitigations are implemented:

**P0 — Loopback binding and per-launch token**
- The embedded Kemal server is explicitly bound to loopback (`127.0.0.1`) to prevent accidental LAN exposure.
- A per-launch cryptographically random token (`Random::Secure.hex(32)`) is generated at startup and required for:
  - All state-changing requests (non-GET)
  - Sensitive read endpoints (`/api/info`, `/api/settings`, `/export.json`, `/`, `/settings`)
- The UI attaches this token via `X-Memo-Token` header (fetch), `memo_token` query/body parameter (forms), or an `HttpOnly; SameSite=Strict` cookie (`memo_token`) set automatically on each protected response.

**P1 — CSRF / Origin hardening**
- `Origin` and `Referer` headers are validated on all token-protected requests. Only requests from the app's own loopback origins (`http://127.0.0.1:<port>` and `http://localhost:<port>`) are accepted.
- `Sec-Fetch-Site` header is additionally checked when provided by the browser; values other than `same-origin` or `none` are rejected.
- WebView startup navigations (opaque/null origin with a valid token) are allowed as a deliberate exception to handle the initial `webview.html=` injection flow.

This project is a desktop application built with **Crystal + WebView**, but it also embeds a **local Kemal HTTP server** and loads the UI over `http://127.0.0.1:<port>`.

Unlike frameworks such as Tauri that provide strict, opt-in APIs and hardened defaults, this application is much closer to a regular web app running on a local HTTP port. As a result, the primary security posture depends on how the local server is bound, what endpoints exist, and what data is exposed.

## Scope / Threat Model

Assumptions to make explicit:

- The app runs on an end-user machine.
- The app stores private notes locally (SQLite database).
- Attackers may be:
  - Another device on the same network (LAN/Wi‑Fi) if the HTTP server is reachable.
  - Another process on the same machine (malware, untrusted local user session, sandbox escape, etc.).
  - A web page opened in a browser on the same machine attempting cross-site requests to the local server.

Non-goals (out of scope for this document):

- OS-level compromise. If the OS is compromised, all local data is at risk.

## Key Risks Identified

### 1) Accidental Network Exposure of the Embedded HTTP Server (High)

The application starts Kemal with a dynamic port. If Kemal binds to `0.0.0.0` (or otherwise listens on non-loopback interfaces), other devices on the same network may be able to reach the app.

Impact:

- Anyone who can connect can access endpoints that read/export notes or modify/delete notes.
- Even with a random port, scanning is feasible on a local network.

Why this is critical:

- The app has no authentication layer.
- The server is intended for local UI only, but network exposure turns it into a remotely reachable service.

### 2) No Authentication / Authorization (High)

All endpoints are effectively “trust whoever can connect.” If another process or device can reach the local server, it can:

- Create, update, or delete notes.
- Export all notes.
- Read metadata such as database path.

### 3) CSRF-like Risks Against Local HTTP Endpoints (Medium–High)

If a browser can reach the local server (especially if the server is reachable from outside the machine), a malicious web page may be able to trigger state-changing requests (e.g., POST requests) even if it cannot read the responses due to CORS.

This is a common risk for “localhost services” that do not implement request origin checks or CSRF protections.

### 4) Sensitive Data Exposure via Convenience Endpoints (Medium)

Endpoints such as exporting notes (e.g., JSON export) are convenient but can become a high-value target if any attacker can reach the server.

Additionally, exposing the database path reveals local filesystem structure and can aid targeted attacks.

### 5) HTML Injection / XSS Footguns in the UI (Low)

The notes list and note content are escaped when rendered server-side, which reduces classic stored XSS risk.

Client-side DOM updates use `textContent` exclusively — no `innerHTML` is currently used in the UI. This significantly reduces the XSS attack surface. Future contributions should continue to avoid `innerHTML` for any user-controlled or server-provided strings.

### 6) Local Data-at-Rest Protection (Medium)

Notes are stored in a local SQLite database without encryption. Risks include:

- Other local users (or malware) reading the database file.
- Backups or disk images leaking the plaintext DB.

Encryption is not always required, but the risk should be acknowledged.

### 7) Environment Variable / Configuration Footguns (Low–Medium)

If the application honors environment variables like `DATABASE_URL`, the app could be pointed to an unintended database location.

Impact:

- Data could be written to a shared location.
- Data could be read from an attacker-provided path.
- Users may accidentally store notes somewhere insecure.

### 8) Supply Chain / Dependency Drift (Medium)

Using dependencies pinned to moving branches (e.g., `master`) increases risk:

- Builds are not reproducible.
- A compromised upstream or unintended change could introduce vulnerabilities.

Also, WebView security depends on the underlying platform web engine (WebKit/WebView2/etc.), so OS/web-engine vulnerabilities can affect the app.

### 9) Navigation / External Content (Medium)

If the WebView can navigate to arbitrary external content (e.g., user clicks a link, or code changes allow external navigation), the external page may attempt to interact with the local server.

Even without a direct JS-to-native bridge, the local HTTP server becomes the primary target.

## Recommended Mitigations (Practical / High-Value)

### A) Force Loopback Binding (Implemented)

As of 2026-06-16 this is implemented:

- Kemal is explicitly bound to `127.0.0.1` to prevent LAN exposure.
- Consider adding a startup self-check that confirms the listening address is loopback-only.

### B) Per-Launch Secret Token (Implemented)

As of 2026-06-16 this is implemented. Even for loopback-only services, a random secret reduces cross-origin / cross-process abuse.

- A cryptographically random token is generated at startup.
- It is required on all state-changing endpoints and sensitive reads.
- It is injected into the UI and sent back through request headers, form/query parameters, or the protected cookie.

### C) CSRF/Origin Hardening (Implemented)

As of 2026-06-16 this is fully implemented:
- `Origin` and `Referer` headers are validated; only the app's own loopback origins are accepted.
- `Sec-Fetch-Site` is checked when present.
- The per-launch token is required on all protected endpoints.

### D) Reduce Data Exposure

- Consider removing or restricting endpoints that reveal local paths.
- Gate exports behind an explicit user action plus token validation.

### E) Avoid `innerHTML` for Untrusted Strings

- Prefer `textContent` and DOM node construction.
- If HTML must be used, sanitize input rigorously.

### F) Consider Data-at-Rest Options

Depending on your target users and threat model:

- Provide an option to encrypt notes (application-level encryption).
- At minimum, document where data is stored and the implications.

### G) Pin Dependencies to Versions/Commits

- Prefer tagged releases.
- If a commit pin is required, pin to a specific commit SHA.

### H) Control WebView Navigation

- Consider preventing navigation away from the local app origin.
- Open external links in the system browser instead of inside the WebView.

## Reporting Security Issues

If you discover a security issue, please report it privately to the maintainer rather than opening a public issue with exploit details.

---

This document is intentionally conservative: desktop apps that embed HTTP servers and web UIs tend to inherit common web-app security risks unless explicitly hardened.
