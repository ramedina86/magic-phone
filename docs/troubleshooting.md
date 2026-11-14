# Troubleshooting

- **Cannot connect:** check the existing systemd unit/foreground process and CLI socket permissions. Try sudo for diagnostics. Set ASTERISK_CONFIG if the daemon uses a nondefault config. Never start a second daemon against the same DB.
- **Missing modules:** inspect asterisk/modules.conf for the required list, check your build and existing module-loading policy. Install/load the matching Asterisk 22 modules; no rebuilding is performed by these scripts.
- **Invalid dialplan/includes:** inspect absolute include paths and permissions, then protected Asterisk logs. Run validate with appropriate read privileges. Conflicting old contexts/endpoints require manual review. Reloads are not a complete syntax validator.
- **Handset registration:** username must match endpoint/AoR name; check password, Pi LAN address, transport/port and router client isolation. Default username is 100; choose another if already used. Status never prints contact URIs.
- **Missing recording:** verify contiguous numbered files and ffprobe format; use -f wav when encoding wav16. Re-deploy to update counts. Check service user read/traverse access to the actual sounds path.
- **AstDB:** status shows the two counters. Use reset-rotation only for the desired playlist. Check actual database path from setup and its service ownership. Do not remove the database to repair unrelated issues.
- **Outbound failure:** keep provider disabled until approved. Check verified account settings, available credit, caller ID policy, registration requirement and Dial status in protected logs. A failed call never tries another contact.
- **One-way/no audio:** check negotiated codec, existing transport NAT settings, host firewall/RTP range and SIP ALG. Ensure handset and Pi can communicate on the LAN. Remove temporary public forwarding; avoid public SIP exposure.
- **Privacy:** raw PJSIP/CLI logs and CDRs can contain numbers/auth exchanges. Do not paste or commit them. The supplied status helper filters sensitive output; private config and backups still require restricted filesystem access.
