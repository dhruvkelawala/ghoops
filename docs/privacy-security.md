# Privacy and security

## What is stored

`~/.local/share/ghealth/records.enc` contains an AES-256-GCM encrypted snapshot of raw and reconciled Google Health records, account binding and per-day collection coverage. A random 32-byte key lives only in macOS Keychain under a namespace derived from the absolute state directory. Every save uses a new random nonce. The envelope version and profile namespace are authenticated. Corruption, missing keys and mismatched namespaces fail closed. Raw records are not rewritten into fabricated observations.

State directories use `0700`; encrypted files and lock files use `0600`. The implementation rejects symlink state paths, symlink files, files owned by another user and group/world-readable private files. Saves use a private temporary file, file sync, atomic rename and directory sync. The cache is a bounded snapshot, not a database service. Other local processes running as this user can still inspect this process's memory; encryption at rest does not protect a compromised account or unlocked process memory.

Keychain holds one OAuth session with access/refresh tokens, client credentials, scopes, expiry and Health user ID, plus the separate cache key. The Web client JSON remains at the owner's external config path; ghoops reads it only for explicit `auth login`, and does not copy it into the repository or a plaintext cache.

## Keychain access

The bridge calls Apple's Security framework directly from the actual installed `~/.local/bin/ghealth`. It does not shell out to `security`, pass secrets as command-line arguments or trust a helper executable. New items trust only this installed executable through `SecTrustedApplicationCreateFromPath` and `SecAccessCreate`. Updating an item changes data only, with no ACL update. Every operation sets `SecKeychainSetUserInteractionAllowed(false)`. A locked Keychain or missing approval returns a failure without approval UI or a plaintext fallback. Rebuilding can require the owner to authorize a changed binary through Keychain Access; ghoops does not automate that approval.

`ghoops doctor --keychain [--json]` reports `exists` and `only_installed_binary` for the selected profile's cache key, OAuth session, serve token and serve devices. A missing item reports both as false. The command inspects access controls without reading item values or changing Keychain.

`doctor --keychain-test` uses a cryptographically random `io.ghealth.probe.<id>` service with a dummy secret supplied to child stdin. Fresh installed-binary processes add it, read/compare it, delete it after comparison, and verify absence. Add refuses an existing service. Deletion requires the expected dummy value. Failure cleanup targets only that service. The probe cannot read or delete a production credential/key namespace or weaken any ACL. It emits no secret values. It proves dummy item access for this executable, not real-item authorization.

Production updates and cross-build probes use the same exclusive advisory installation lock, private candidates and recoverable backup. Candidates must have a certificate-backed stable `io.ghealth.cli` signature compatible with production. Empty and ad-hoc identities are refused. Target fingerprints and lock ownership are checked before effects; arbitrary noncooperating filesystem writers can still race these checks.

Cross-build cleanup runs only through the owned installed executable, because a private backup is not authorized by the Go Keychain policy. Cleanup confirms absence or matches the expected random dummy value before deletion. If another writer replaces production, the check refuses to execute its replacement and retains the private scoped recovery data. Handled termination before installation commitment triggers cleanup and restoration. Commitment occurs at an empty pending-signal snapshot while SIGTERM/SIGINT are blocked; later handled cancellation does not turn committed success into failure. The cross-build probe always restores production and never commits a new installation. SIGKILL and power loss cannot run cleanup. Restoration or cleanup failure is reported rather than claimed successful. Recovery directories use `0700`, and dummy recovery JSON uses `0600`. Never put retained recovery files into Git.

## Network and OAuth

Health requests use fixed Google v4 read routes with bearer tokens in headers. v2 roll-up requests use POST for read-only aggregation. OAuth POSTs exchange/refresh tokens; `auth logout --revoke` is an explicit revocation request. No health writes or nutrition scopes are used. v2 also requests read-only profile, settings, IRN and location scopes; location is used only by explicit TCX export. The CLI never sends local health records to an assistant, a model or another service. The user can explicitly consume its JSON output.

HTTP requests have a 30-second timeout, redirect refusal and response size limits. Transient health failures have bounded retries. 429/5xx responses honor integer or HTTP-date `Retry-After` within a 60-second wait budget; longer waits fail instead of retrying early. Finite commands have a ten-minute total context and handle termination; the local API server runs until stopped. Provider error bodies, tokens, OAuth codes and callback queries do not appear in error messages. The explicit consent URL contains client ID, state and PKCE challenge, but no client secret, verifier or token. Treat that short-lived URL privately.

The listener binds `127.0.0.1` over IPv4 with exact host/path/method checks, strong random state, constant-time comparison, duplicate-state rejection, one-time consumption, bounded headers/timeouts and no callback request log. A failed state check does not consume a valid flow. Tokens are persisted before refresh returns them to callers. File locks serialize refresh across processes and serialize collection and login/logout against cache mutations. Logout therefore waits for a running sync. Reports can read the previous atomic snapshot during sync.

## Data semantics and lifecycle

v1 reports generate no scores. v2 generates the documented estimates in docs/v2/scores.md and never diagnoses. Trends are arithmetic summaries of present, unambiguous measurements with coverage counts. Device coverage, upstream processing delays and consent determine availability. A current missing day does not reuse yesterday's value. Unsupported and permission-denied streams remain explicit, and retained values after failures are marked stale/unavailable. See the [JSON contract](v2/contract.md).

Logout retains the encryption key and cache so local summaries remain readable. To erase local health data, the owner can remove the profile directory and delete only its matching `io.ghealth.signed.v1.<profile hash>.cache-key` item using Keychain Access. Initial ad-hoc installations used `io.ghealth.<profile hash>.cache-key`; these retained legacy items are separate and are not deleted or re-trusted by signed installation. The profile hash derives from its absolute state directory. Removing only a key makes its corresponding records unrecoverable but leaves encrypted bytes on disk. v1 has no retention scheduler. v2 retains at most 400 days during saves. Backups can retain encrypted bytes and exported data.

Explicit `data export` produces plaintext. Its output is private health data and must be kept outside Git, logs and chat. File export refuses overwrite and uses `0600`; stdout export inherits the caller's destination and logging behavior. The repository contains only explicitly synthetic test records. Ignore rules reduce accidental inclusion but are not a substitute for inspecting staged files. Live verification reports counts only and does not publish raw records.

## Version 2 store

`records-v2.enc` is separate from `records.enc` and uses AES-256-GCM with the existing Keychain cache key. Its authenticated header is `ghealth-cache-v2\n`, so the formats cannot be interchanged. It holds raw provider records, minute heart-rate roll-ups, daily roll-ups, user resources, coverage and collection runs. Atomic saves retain 400 days. The v2 collector uses `collect.lock`; v1 continues to use its own store and lock.

## Local HTTP server and pairing

`ghoops serve` binds only to IPv4 `127.0.0.1`, port 8787 by default. Tailscale Serve provides HTTPS within your tailnet. Keep Funnel off. Health requests use bearer credentials. The Mac stores one credential hash per device in Keychain and compares hashes in constant time.

Run `ghoops pair` on the Mac. Scan the QR inside ghoops or paste the line on the Pairing screen. The code can be used once within five minutes. Check the address on the iPhone, then compare the six-digit codes and approve on the Mac. The iPhone saves its address and device credential together in a Keychain record that stays on that phone. An existing pairing works until the first device approval retires its old credential.

A paired iPhone can read the health history available from your Mac, including scores, heart rate, workouts, sleep and journal answers. It can add and edit workouts, save sleep edits, rate effort and save journal answers on the Mac.

Tap **Unpair** to remove the pairing, saved scores, uploaded workout copies and waiting edits from that iPhone. The alert asks whether to keep or delete workouts still waiting for that Mac, including a running session. Kept workouts wait for the same Mac profile to pair again. The iPhone can back up work that is still waiting. The phone excludes saved scores and uploaded workout copies from backup.

To revoke access from the Mac, list devices with `ghoops pair devices`, then run `ghoops pair revoke <device-id>`. Omitting the ID revokes all pairings. Revocation takes effect within five seconds. The next confirmed 401 clears the phone's saved snapshot. Widget and Live Activity health readings follow iOS access settings for the locked phone.

`ghoops auth logout` removes the Mac's Google credentials and stops new imports. Paired devices can still use the data already on the Mac.

The server caps request sizes, reads each request within 15 seconds and sends `Cache-Control: no-store`. Logs contain time, method, route template, HTTP status and duration.

## LaunchAgents and logs

`schedule install` installs `io.ghealth.collect` every 30 minutes and `io.ghealth.serve` with KeepAlive in the user's login session. Both run the installed binary. Logs under `~/.local/share/ghealth/logs/` use a `0700` directory and `0600` files. Collection logs hold counts and statuses; server logs hold the request fields above. Each collect run truncates either log when it exceeds 1 MiB. Keychain access after reboot requires the user's login session; failures leave old collection freshness visible. `schedule uninstall` removes both agents and leaves encrypted records intact.

## TCX export

`workout export-tcx` makes an explicit read request and writes raw TCX bytes to a new `0600` file, refusing overwrite. TCX can contain plaintext GPS tracks and workout details. It is never fetched during collection or exposed by the local HTTP API. Keep exported files outside the repository, shared directories and logs, and delete temporary checks after use.
