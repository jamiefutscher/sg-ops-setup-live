# sg-ops-setup-live

Live channel for the Spirited Gifts PC build (SG-Setup). Every station PC runs the `SG-Update` task (3:30 AM and 10 min after boot), which reads `VERSION.txt` here, and when it changes downloads every file listed in `manifest.txt` and re-runs setup silently.

To push an update: change the files, bump `$ScriptVersion` in `SG-Setup.ps1` and `VERSION.txt`, commit to `main`. No secrets live here — the Webroot keycode and Google enrollment tokens come from `secrets.txt` on the thumb drive and are kept on each PC at `C:\SGSetup\secrets.txt`.
