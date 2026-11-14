# Magic Phone — Asterisk Configuration Repository

## 1. Overview

Build a small, reproducible GitHub repository for a child's telephone powered by **Asterisk 22.x** on a **Raspberry Pi Zero 2 W**. Asterisk handles calls, audio playback and sequential playlists. Shell scripts handle setup, private configuration, deployment and diagnostics.

**Keep version 1 simple:** no Python, Docker, Node.js, web UI, database server, audiobook bookmarking, skip controls, or arbitrary telephone dialing. Asterisk's embedded **AstDB** may store playlist counters.

### Target environment

| Item | Target |
| --- | --- |
| Computer | Raspberry Pi Zero 2 W, 512 MB RAM |
| OS | Raspberry Pi OS / Debian 13 Trixie, ARM64 |
| PBX | Asterisk 22.x, already built from source |
| Signaling | PJSIP; local handset registered to the Pi |
| External calls | HaloNet SIP provider (registration pending) |
| Network | Private LAN behind NAT; no public SIP port forwarding |
| Deployment | Bash scripts and existing systemd service |

The installer **must not** reinstall the OS or rebuild Asterisk. Detect actual Asterisk paths, service state and configuration locations instead of blindly assuming defaults.

## 2. Dial plan and user experience

| Extension | Name | Expected behavior |
| --- | --- | --- |
| **101** | Welcome | Play the bundled greeting “Hi Bob, your magic phone is working,” then hang up |
| **102** | Audiobooks | Play one file from the audiobook playlist, advance the counter and hang up |
| **103** | Music | Play one file from the music playlist, advance the counter and hang up |
| **201** | Babcia | Dial her configured Polish mobile number via HaloNet |
| **202** | Mum | Dial her configured Polish mobile number via HaloNet |
| **203** | Dad | Dial his configured Polish mobile number via HaloNet |
| **204** | Contact #4 | Optional; dial its private configured number if present |
| **205** | Contact #5 | Optional; dial its private configured number if present |

The five family extensions are the **only** routes to the public telephone network. Numbers must never be committed. No emergency-number override, especially no internal mapping of `112`.

### 101 — Welcome

- Answer the call, play a committed placeholder WAV, then hang up.
- Users can replace the recording locally without editing the dialplan.
- The default recording must be a real playable audio file (not a text file with a `.wav` extension).

### 102 and 103 — Simple rotation

- Separate folders, file counts and persistent counters for audiobooks and music.
- Each call plays **exactly one** sequentially numbered audio file.
- Numbering starts at `1` with no gaps; after `N`, wrap around to `1`.
- Advance the counter **before** playback, so early hangups still advance.
- Counters persist across Asterisk restarts/reboots in AstDB (for example `magic/audiobook_next` and `magic/music_next`).
- No resuming playback position, no keypad commands, no shuffle and no file discovery at call time.
- Empty playlists or missing files must produce an understandable, safe failure (for instance, a bundled unavailable announcement or a short log message and hangup).
- Document that simultaneous calls to one playlist are not guaranteed atomic in v1; the intended setup uses one child handset.

### 201–205 — Family calls

- The contact mapping is private, configurable and validated during setup.
- Phone numbers use E.164 format, e.g. `+48XXXXXXXXX`; translate to the provider's required dial string only at the trunk boundary.
- `201`–`203` are intended for Babcia, Mum and Dad; `204` and `205` are optional.
- If a contact is not configured, it must **not** place an outbound call; play an unavailable prompt or end with a clear message.
- Each call has a configurable duration cap (default **30 minutes**), plus a configurable ring timeout.
- Handle busy, no-answer, failed or unavailable SIP trunk without leaking credentials or calling another destination.
- Inbound PSTN calling is out of scope for v1.

## 3. Repository structure

```text
magic-phone/
├── README.md
├── SPEC.md
├── .gitignore
├── .env.example
├── asterisk/
│   ├── extensions.conf
│   ├── pjsip.conf
│   ├── modules.conf
│   └── templates/
│       ├── sip-trunk.conf.example
│       ├── contacts.conf.example
│       └── local-phone.conf.example
├── scripts/
│   ├── setup.sh
│   ├── configure.sh
│   ├── deploy.sh
│   ├── validate.sh
│   ├── status.sh
│   └── reset-rotation.sh
├── config/
│   └── settings.example
├── audio/
│   ├── welcome/
│   │   └── placeholder.wav
│   ├── audiobooks/
│   │   └── .gitkeep
│   └── music/
│       └── .gitkeep
└── docs/
    ├── installation.md
    ├── sip-provider.md
    ├── audio-format.md
    └── troubleshooting.md
```

The coding agent may refine filenames or separation of generated vs. committed files if it explains the decision and preserves all requirements.

## 4. Asterisk configuration design

- Use a dedicated `[magic-phone]` dialplan context for the child's handset. Keep access to outbound calls confined to explicit contact extensions.
- Use PJSIP (`pjsip.conf` and included private fragments), not legacy `chan_sip`.
- Preserve the user's existing working Asterisk installation and SIP endpoint where possible; never overwrite all of `/etc/asterisk` without review and backup.
- Prefer separate owned include files over replacing global sample configurations. Design around real Asterisk `#include` semantics and validate the deployed include paths.
- Provide a committed, safe public configuration plus **generated local-only** secrets/contacts; use examples with obvious placeholders such as `REPLACE_ME`.
- Local SIP endpoint: initial default username `100`, with a password entered interactively and never committed. Make server addresses configurable, not hardcoded to an earlier DHCP lease.
- Support G.722 for wideband playback where negotiated, with G.711 (`ulaw`/`alaw`) fallback. Confirm the actual modules are available before deployment.
- Preserve Asterisk's actual DB file and counter state on deployments. Do not hardcode its location.
- Do not enable unrelated sample listener modules or public management interfaces merely to support this project.
- Reload dialplan/PJSIP where sufficient; restarting is acceptable only when transport changes or the chosen configuration demands it.

### Rotation implementation

Implement the rotation with standard Asterisk dialplan expressions, `DB()` / AstDB and `Playback()`. Keep track counts in generated, non-sensitive settings or Asterisk variables that can be updated at deploy time. Ensure initial missing counters start at 1 and validation rejects zero/negative counts. Reference audio using extensionless playback paths, such as `custom/magic-phone/audiobooks/${TRACK}`.

### Provider trunk

- Target HaloNet, but obtain and verify the customer's actual SIP domain, registration, authentication, dialing format and caller ID requirements after verification.
- Do not invent credentials or assume every account uses identical settings.
- Use outbound registration if required by the provider and compatible NAT settings; avoid inbound public forwarding by default.
- Keep all auth details in generated ignored files with permissions appropriate for the Asterisk service account.
- Validate the five private destinations and only allow direct mappings to those entries.
- Provide a way to configure audio-only features before HaloNet is available.
- Avoid generic `_X.` patterns or other broad external-dialing escape routes in the child's context.

## 5. Audio specification

| Use | Format |
| --- | --- |
| Welcome and short prompts | `.wav`, mono, 16-bit signed PCM, 8 kHz |
| Audiobooks and music | Asterisk `.wav16` (WAV container), mono, 16-bit signed PCM, 16 kHz |

Asterisk `Playback()` uses basenames without extensions. Wideband results depend on the actual negotiated phone codec.

Document example conversions with FFmpeg:

```bash
ffmpeg -i input.mp3 -ar 8000 -ac 1 -c:a pcm_s16le greeting.wav
ffmpeg -i input.mp3 -ar 16000 -ac 1 -c:a pcm_s16le story.wav16
```

Version 1 requires contiguous numeric filenames (`1.wav16`, `2.wav16`, ...). Keep master recordings elsewhere if higher fidelity is important. The Pi has limited storage and memory; do not transcode on every call.

### Git handling

- Commit **only** `audio/welcome/placeholder.wav` as playable example audio, plus `.gitkeep` files.
- Ignore all other audio under `audio/` including user recordings; ensure an explicit `.gitignore` exception keeps the placeholder tracked.
- Ignore generated files, credentials, phone numbers, private configuration and backups.
- Do not log SIP secrets, store them in command history, or commit example files containing actual personal numbers.

### Deployment of audio

Copy to a predictable subdirectory such as `/var/lib/asterisk/sounds/custom/magic-phone/{welcome,audiobooks,music}/`, maintaining safe ownership and file permissions. Validate file format and sequential numbering. Never delete user audio on a normal redeploy; provide an explicit optional pruning operation if needed.

## 6. Shell helpers

Use Bash with `set -euo pipefail`, clear diagnostics, safe quoting, input validation and idempotent behavior wherever possible. Do not add Python as a dependency. Avoid storing secrets in process command-line arguments or world-readable temporary files. Scripts should have a documented privilege model rather than demanding root unnecessarily.

### `scripts/setup.sh`

- Verify OS, architecture and Asterisk binary/version.
- Detect paths and current systemd service or foreground-running Asterisk.
- Check required dialplan, sound-file and PJSIP modules.
- Prepare project-owned directories/permissions as needed.
- **Do not** reinstall Asterisk, alter OS repositories, or replace the systemd unit by default.

### `scripts/configure.sh`

- Interactive helper that asks for local handset SIP user/password, optionally HaloNet SIP credentials, server/transport if required, and contact numbers.
- Ask for configurable maximum call duration, ring timeout, audiobook count and music count (or derive counts from validated media at deployment).
- Accept an incomplete provider setup while verification is pending.
- Validate the five numbers, normalize Polish numbers to `+48...` and allow contacts `204`/`205` to remain unset.
- Hide password entry; render private files with restrictive permissions (normally `0600`, adjusted as needed for the actual service user).
- Never echo sensitive values to logs or standard output.
- Support safe reconfiguration without discarding existing secrets not being changed.

### `scripts/deploy.sh`

- Back up affected existing Asterisk files before editing.
- Generate/install project-owned dialplan and PJSIP includes and private fragments.
- Install/validate the bundled welcome WAV and user-provided media.
- Preserve AstDB rotation state and unrelated user files.
- Run checks before applying; offer a dry-run/diff where feasible.
- Reload the dialplan and PJSIP when possible; restart only if necessary and clearly report that calls may be interrupted.
- Include documented rollback instructions and fail without leaving a partially broken configuration wherever practicable.

### `scripts/validate.sh`

Check Asterisk binary/version, module availability, service connectivity, expected paths, audio codec/container formats and consecutive numbering, positive playlist counts, include resolution, PJSIP endpoints/trunk status, secret permissions and no unrestricted PSTN patterns. Separate warnings from errors. An unconfigured HaloNet trunk is a warning during local-only setup, not a deployment blocker.

### `scripts/status.sh`

Show systemd/Asterisk health, handset registration, optional trunk status, active calls, installed audio counts and current AstDB next-track counters. Mask phone numbers and never print credentials.

### `scripts/reset-rotation.sh`

Support:

```bash
./scripts/reset-rotation.sh audiobooks
./scripts/reset-rotation.sh music
./scripts/reset-rotation.sh all
```

Reset only the relevant next-track counter(s) to `1`; do not alter files or other state.

## 7. Security and child-friendly constraints

- The child's handset can dial **only** local features `101–103` and explicit family speed dials `201–205` in the project context.
- Asterisk must not allow outbound dialing of arbitrary telephone numbers via patterns or alternate contexts.
- No SIP/RTP forwarding to the Pi from the public internet by default; remove temporary troubleshooting port forwards.
- Strong SIP passwords and limited filesystem access to credential files.
- Default PSTN call-duration cap of 30 minutes; recommend HaloNet prepaid credit/spending controls where available.
- A service outage or missing contact must not cause fallback to a different person or paid destination.
- Do not silently convert `112` into an internal speed dial.
- Explain that the v1 phone **is not a substitute for access to emergency services**; emergency calling and emergency-service routing are out of scope.
- Avoid introducing a permanent web UI, AMI/ARI exposure or other network attack surfaces.

## 8. Documentation deliverables

**`README.md`**: purpose, extension table, prerequisites, quickstart, deployment and rollback, common diagnostics, security warning and ways to update audio.

**`docs/installation.md`**: setup on existing Asterisk 22, backups, interactive configuration, service integration, audio deployment and tests.

**`docs/sip-provider.md`**: obtaining HaloNet credentials, PJSIP registration/trunk setup after account approval, outbound caller ID, dialing format, NAT troubleshooting and two-way audio checks. Mark unverified provider values as placeholders.

**`docs/audio-format.md`**: audio specs, FFmpeg conversion, naming rules, rotation semantics, count updates and reset instructions.

**`docs/troubleshooting.md`**: missing service, invalid dialplan, PJSIP registration, missing recording, AstDB, outbound call failures, no/one-way audio, NAT and router isolation.

## 9. Quickstart target

The repository should support a documented workflow similar to:

```bash
git clone <repository-url>
cd magic-phone
./scripts/setup.sh
./scripts/configure.sh
./scripts/validate.sh
sudo ./scripts/deploy.sh
./scripts/status.sh
```

The implementation agent may choose a safer privilege structure (e.g. `sudo` for setup/deploy only) and should ensure prompts, passwords and file permissions remain correct across privilege changes.

## 10. Acceptance tests

### Audio

- `101` plays the bundled placeholder and hangs up.
- With 3 audiobook files, four successive calls to `102` play tracks `1, 2, 3, 1`.
- With 2 music files, three successive calls to `103` play tracks `1, 2, 1`.
- Music and audiobook counters advance independently and survive Asterisk restart/reboot.
- Early hangup still advances the relevant playlist.
- Missing files and empty playlists fail safely and observably.

### Family calling

- `201` calls only Babcia; `202` only Mum; `203` only Dad.
- `204` and `205` work only when configured and otherwise fail safely.
- Only five configured destinations can create paid calls; arbitrary digits cannot.
- Tests confirm ringing, no-answer, busy, provider failure and two-way audio.
- Call-duration cap works.
- Provider-absent local-only installation remains usable.

### Deployment and security

- A fresh clone installs configuration on an existing compatible Asterisk 22 system, without rebuilding Asterisk.
- Repeated deployment does not duplicate includes or wipe private files/state.
- Backup and rollback are documented and work.
- Real SIP credentials, destination numbers and user audio do not appear in `git status` or committed history.
- The placeholder WAV **does** appear in version control and is playable.
- Asterisk is not exposed directly to the public internet by default.
- No internal `112` mapping exists.

## 11. Explicitly out of scope (v1)

- Dynamic weather/time announcements.
- Python or shell commands invoked during calls.
- Audiobook resume position, skipping, pause controls and playlists generated dynamically.
- Web interface, database server, Docker, CI deployment to the Pi and remote management dashboard.
- Caller voicemail, inbound PSTN calls/DID, family ring groups and speech recognition.
- Emergency call routing.
- Automatic Asterisk source compilation and OS distribution upgrades.

## 12. Instructions to the coding agent

Implement this specification as a complete, reviewable Git repository, **not** just an outline. Include a working sample WAV and functioning Asterisk 22 dialplan/PJSIP templates, with safe and executable shell helpers. Keep the solution minimal, explain assumptions, and do not invent real SIP credentials, phone numbers, hostname, LAN IP or provider settings. Where the correct behavior depends on the real HaloNet account, generate clear placeholders and ask for that information during setup. Prioritize safe changes to the existing Asterisk installation and make local audio features work before the SIP trunk is available.
