# Installation and rollback

Start with Asterisk 22 already built and running on ARM64 Trixie. Install FFmpeg separately if absent. Run setup to inspect the actual runtime config/data paths and loaded modules. For custom `asterisk.conf`, specify `ASTERISK_CONFIG`. A missing service is not an installation failure if a foreground daemon is reachable. Setup reports matching systemd units but never creates or replaces one. Configure service restart policy through your existing administrator workflow.

Review existing transports with `asterisk -rx 'pjsip show transports'`. Supply their name during configure. The installer deliberately reuses these to avoid transport restarts and listener exposure. Review NAT/local_net/external signaling/media address values in that existing transport with your administrator. If transport changes are necessary, arrange a maintenance window and restart your actual service; this interrupts calls. Never add public router forwarding for this project.

Run configure without sudo. Files are data, not sourced shell: `.private` is 0700 and settings 0600. Reconfiguration retains unchanged secrets and provider settings when disabling the trunk. Private deployed includes are 0640, owned by the detected running Asterisk account/group. Root-only deployment backups contain secrets. Use a dedicated service account. Scripts must be run from a trusted checkout.

Run validate, deploy --dry-run, then deploy as root. Deployment refuses namespace/endpoint collisions, reuses root configs and adds project-owned absolute includes. It serializes deployments, backs up roots, owned config and audio, validates before changing files, and attempts automatic file restoration/reload if a later step fails. CLI reload can report partial errors without a failing exit code: deployment checks that the main context and handset endpoint are loaded but does not constitute a full Asterisk parser or live-call test. Review protected Asterisk logs after deployment. Do not edit the generated includes directly.

## Manual rollback

Stop calls and select the exact backup path reported by deploy. With root privileges, copy `extensions.conf` and `pjsip.conf` from that backup over the matching files in the detected config directory. Move the current `magic-phone` config subdirectory aside; restore backup `owned` to `magic-phone` if it exists (absence means this was first installation). Read the backup `audio-path` file, move that exact sound directory aside and restore backup `audio` there if present. Preserve ownership/modes with `cp -a`. Do not touch the AstDB path. Reload with the same Asterisk binary/config selection using `dialplan reload` and `pjsip reload`. Verify 101 and handset registration. Files moved aside contain secrets; keep them root-only. Do not roll back roots if another administrator edited them subsequently without merging those edits.

## Acceptance checklist on the Pi

- 101 plays the committed spoken greeting and hangs up.
- With three books, call 102 four times: 1,2,3,1. With two songs, call 103 three times: 1,2,1.
- Hang up early and confirm the next call advances; restart the existing service/reboot and confirm both independent counters survive.
- Try an empty playlist and a temporarily missing installed file: log and hangup, no outbound call.
- With provider disabled, 101–103 work and 201–205 cannot dial.
- With verified provider, test each configured family mapping, optional missing contacts, busy, no-answer, trunk outage and two-way audio. Set a short duration cap for a test and restore 1800 afterward.
- Arbitrary numbers and 112 must have no route; transfers/redirects must not escape the allowed destinations.
- Repeat deployment and compare include counts; verify no AstDB loss, stale audio retained, unrelated files unchanged. Exercise manual rollback.
- Check `git status --ignored`: only placeholder.wav is trackable audio; private credentials/numbers remain ignored.

## Reusing an existing handset

Choose `existing` handset mode in configure to preserve its authentication and AoR configuration. Before deploying, back up its owning config and change that endpoint's context to `magic-phone`, set `allow_transfer=no`, `allow_subscribe=no`, `direct_media=no`, and allow `g722,ulaw,alaw`. Reload PJSIP and verify those fields. This temporarily disables handset features until the project dialplan is deployed. Existing mode does not generate or overwrite that endpoint/auth/AoR; it checks the loaded context and transfer restriction. Keep the migration backup separately for rollback. Managed mode remains the default for a new endpoint.
