# ghoops

This is an early release. So far, only the author runs ghoops.

ghoops collects Fitbit and Pixel Watch data through the Google Health API and stores it encrypted on your Mac. The Mac estimates Recovery, Strain and Sleep performance from that data. An iPhone app and its widgets show your scores over Tailscale. The scores are estimates for personal use. [How scores are calculated](docs/v2/scores.md)

## Requirements

- A Mac with an unlocked login Keychain, Xcode 27.2 and Apple's command-line tools.
- Go 1.27.4 or later with CGO, Python 3 and XcodeGen. Put `go`, `python3` and `xcodegen` on your PATH.
- A Fitbit or Pixel Watch linked to a personal Google account that you can use with Google Cloud.
- An iPhone on iOS 26 or later and an Apple ID for signing. A free Apple ID works with a rebuild and reinstall every 7 days.
- Tailscale on the Mac and iPhone, signed in to the same tailnet.

Clone the repository on your Mac.

```sh
git clone https://github.com/dhruvkelawala/ghoops.git ghoops
cd ghoops
```

## Google setup

Create the Google Cloud project, configure OAuth and save the client JSON before signing in. [Google setup guide](docs/google-setup.md)

## Build and install

In Xcode, open **Settings → Accounts** and add your Apple ID. If you need a code-signing identity, select your team and create an **Apple Development** certificate in **Manage Certificates**.

Run these commands in the checkout. Replace `<signing identity>` with the certificate hash from the first command.

```sh
security find-identity -v -p codesigning
make SIGN_IDENTITY='<signing identity>' install
export PATH="$HOME/.local/bin:$PATH"
ghoops version
ghoops doctor --keychain-test
```

The installer runs the fixture checks and signs `~/.local/bin/ghealth`. It creates the `ghoops` command as a symlink. For updates, pull the latest changes and run the install again with the same identity so Keychain access keeps working. Add the PATH line to your shell startup file if you want to run `ghoops` in new terminals.

## First login

```sh
ghoops auth login --client-file "$HOME/.config/ghealth/client.json"
ghoops auth status
```

Approve access in the browser on the same Mac. The callback returns to the CLI, which stores your tokens in Keychain. `ghoops auth status` checks the local credentials.

## Background collection

```sh
ghoops collect
ghoops schedule install
ghoops schedule status
```

The first command imports data. The schedule starts the local server and runs collection at login and every 30 minutes while your Mac is awake and you are logged in. After a reboot, log in to resume collection.

## Tailscale and pairing

Run this on the Mac. It lets your iPhone reach the local server over HTTPS within your tailnet. Use Tailscale Serve and keep Funnel off.

```sh
tailscale serve --bg --https=8787 http://127.0.0.1:8787
ghoops pair
```

Keep the QR code and pairing link private. Leave the code open in the terminal while you build the app.

## Build the iPhone app

Create `~/.config/ghealth/ios-identity` with your Team ID, a unique bundle ID prefix and an App Group, one `KEY=value` per line. Leave `.app` off the prefix: the app, widget and UI test bundle IDs add `.app`, `.app.widgets` and `.app.uitests`. The App Group starts with `group.`. To keep the file somewhere else, set `GHOOPS_IOS_IDENTITY` to its path. `make ios-project` reports a missing file or key. [iPhone build targets](docs/v2/app.md#22-make-targets-repo-root-makefile)

```ini
TEAM_ID=<Team ID>
BUNDLE_ID_PREFIX=<bundle ID prefix>
APP_GROUP=group.<bundle ID prefix>
```

```sh
make ios-project
open ios/GHealth.xcodeproj
```

In Xcode, use automatic signing with your team for the app and widgets. Connect your iPhone, select it as the destination for the **GHealth** scheme and click **Run**. Enable Developer Mode on the iPhone if prompted.

Scan the pairing code with the iPhone Camera and open it in ghoops. You can also paste the private link into the app's Pair screen. Today loads your available scores. You can add ghoops widgets from the iPhone's widget gallery.

## Set your profile

ghoops reads your age from your Fitbit profile when it is available. If you know your maximum heart rate, you can enter it in beats per minute. Replace `<bpm>` with your value.

```sh
ghoops config set max_hr_override_bpm '<bpm>'
```

Strain uses the male-derived TRIMP profile `banister_b192` by default. To use the female-derived profile, run this command.

```sh
ghoops config set trimp_profile banister_b167
```

## If sign-in stops

If collection reports an authorization error such as `invalid_grant`, sign in again with the same account. Your collected data stays on disk.

```sh
ghoops auth login --client-file "$HOME/.config/ghealth/client.json"
ghoops collect
```

## Known limits

- Scores and history use London dates.
- Google OAuth Testing mode may require `ghoops auth login` again as often as once a week. Your collected data stays on disk.
- With a free Apple ID, rebuild and reinstall the app from Xcode every 7 days. The paid Apple Developer Program removes the weekly rebuild.
- ghoops supports one Google account per Mac.
- Some scores show **Calibrating** until ghoops has collected enough nights.

## Assistants

Use `ghoops --json brief` for a local summary. It reports statuses and bands by default. Check for schema version 2 and `freshness.collector_stale`. When a score is empty, report its status and reason. Include the response's note that the scores are estimates. [JSON contract](docs/v2/contract.md)

## Privacy

Health data stays on your Mac and iPhone. The Mac encrypts the store with a key in Keychain. The local server listens on loopback and requires the pairing token. [Privacy and security](docs/privacy-security.md)

## Contributing

Open a GitHub issue to discuss a change or report a bug. Include the steps to reproduce it and your macOS or iOS version. Use synthetic data in examples and run `make check` before submitting code. [Private vulnerability reporting](SECURITY.md)

## License

MIT. See [LICENSE](LICENSE). The bundled fonts use the SIL Open Font License; their notices are in `ios/Shared/Fonts`.

ghoops is an independent project. It is not affiliated with or endorsed by WHOOP, Google or Fitbit, and their names are trademarks of their owners.
