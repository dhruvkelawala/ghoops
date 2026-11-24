# Set up Google Health for ghoops

Use a personal Google account and a Fitbit or Pixel Watch. You'll create an OAuth client for your own Mac and authorize it with that same account.

## Create a project and enable the API

1. Open the Google Cloud console. In the project selector, choose **New Project**, give the project a name and click **Create**. Select the new project. [Google Cloud setup](https://developers.google.com/health/setup)
2. Open **APIs & Services → Library**, search for **Google Health API** and click **Enable**. [Google Health API setup](https://developers.google.com/health/setup)

## Configure Google Auth Platform

1. Open **Google Auth Platform → Branding**. Start setup if prompted, give the app a name and fill in the support and contact fields. [Google OAuth setup](https://developers.google.com/health/setup)
2. In **Audience**, choose **External** and leave the publishing status set to **Testing**. Under **Test users**, add the personal Google account you will link in the Google Health app. [Google's audience settings](https://support.google.com/cloud/answer/15549945)
3. In **Data Access**, click **Add or remove scopes** and add all seven read scopes below. [Google Health API scopes](https://developers.google.com/health/scopes)

   ```text
   https://www.googleapis.com/auth/googlehealth.sleep.readonly
   https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly
   https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly
   https://www.googleapis.com/auth/googlehealth.profile.readonly
   https://www.googleapis.com/auth/googlehealth.settings.readonly
   https://www.googleapis.com/auth/googlehealth.irn.readonly
   https://www.googleapis.com/auth/googlehealth.location.readonly
   ```

4. In **Clients**, click **Create Client** and choose **Web application**. Add `http://127.0.0.1:8765/oauth/callback` under **Authorized redirect URIs**. Create the client and download its JSON. [Google's OAuth client setup](https://developers.google.com/health/setup)

## Save the client and link your account

Save the downloaded JSON as `~/.config/ghealth/client.json` with mode `0600`. Replace `<downloaded client filename>` with the name of the JSON file in Downloads.

```sh
mkdir -p "$HOME/.config/ghealth"
install -m 0600 "$HOME/Downloads/<downloaded client filename>" "$HOME/.config/ghealth/client.json"
```

The JSON contains your client secret. Keep it private and delete the download once you have the private copy in place.

In the Google Health app on your phone, sign in with the Google account you added as a test user. Create a profile or move your existing Fitbit account to that Google account, then sync your Fitbit or Pixel Watch. [Google Health account setup](https://developers.google.com/health/setup) · [Move a Fitbit account](https://support.google.com/googlehealth/answer/14237024)

## Sign in and check access

Install the Mac CLI before running these commands. [Build and install ghoops](../README.md#build-and-install)

```sh
ghoops auth login --client-file "$HOME/.config/ghealth/client.json"
ghoops auth status
ghoops probe --v2
```

Sign in on the Mac with the linked account and approve all seven read permissions. In Testing, Google may warn that the app is unverified. Check that the prompt names the app you just created. [Google's Testing mode](https://support.google.com/cloud/answer/15549945)

`auth status` checks your saved sign-in locally. `probe --v2` contacts Google Health and reports statuses and record counts. Once the probe can reach your streams, continue with background collection. [Background collection](../README.md#background-collection)

## FAQ

### Google reports `invalid_grant`

Run the sign-in command again with the same Google account. Testing mode can expire a refresh token after 7 days. Your collected data stays on the Mac. [Google's refresh token rules](https://developers.google.com/identity/protocols/oauth2)

### Google returns 400 `ACCOUNT_NOT_LINKED`

Open the Google Health app, sign in with the same Google account and finish setting up the profile or moving the Fitbit account. Then try signing in to ghoops again. [Google Health troubleshooting](https://developers.google.com/health/troubleshooting)

### Google returns 403

Check that the project which issued the OAuth client has access to the Google Health API and that you granted the requested read permissions. A legacy Fitbit login can also cause a 403. Move that account to Google and retry with the linked Google account. [Google Health troubleshooting](https://developers.google.com/health/troubleshooting) · [Move a Fitbit account](https://support.google.com/googlehealth/answer/14237024)

### Can I use my work or school Google account?

Google Workspace accounts cannot link to Google Health. Use a personal Google account. [Google account requirements](https://support.google.com/googlehealth/answer/14237024)

### Which devices does ghoops support?

ghoops supports data from Fitbit and Pixel Watch. [Google Health API device support](https://developers.google.com/health/about)

### Why do my scores show Calibrating?

Some scores need several nights of data to build your baseline. Keep your watch syncing and let ghoops collect more nights. [Score inputs and baselines](v2/scores.md)
