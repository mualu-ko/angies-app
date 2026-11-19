# Angie's App — patient app (phase 1)

Flutter app for patients on oral anticancer medicine. It handles dose alarms that work offline, an adherence log, side effect (ADR) reports, and drug info with interaction alerts.

The project has two parts:

- **Patient app** (Android). Alarms work fully offline.
- **Clinician portal** (web, `lib/portal/`). Clinicians review side effect reports, approve medicines patients tell us about, and watch adherence.

Both sync through Firebase. The hospital link and SMS are still mocked.

## First-time setup (Windows)

You need Flutter installed (`flutter doctor` should pass for Android) and an Android phone with USB debugging on.

```powershell
cd "C:\Users\Mwaluko\Documents\Angie's App"
powershell -ExecutionPolicy Bypass -File .\setup.ps1
flutter run
```

`setup.ps1` does four things:

1. Generates the Android project files with `flutter create`.
2. Keeps our code and `AndroidManifest.xml`.
3. Sets `minSdk 23` and Kotlin 2.x, which the `alarm` package needs.
4. Runs `flutter pub get`.

If the build fails with strange path errors, the apostrophe or space in `Angie's App` is the likely cause. Copy the folder to something like `C:\dev\angies_app` and run the script again.

Run the unit tests with `flutter test`.

## Firebase setup (one time)

In the [Firebase console](https://console.firebase.google.com):

1. **Create a project**, for example `angies-app`. You can skip Google Analytics.
2. **Authentication** > Sign-in method: enable **Anonymous** (used by the patient app) and **Email/Password** (used by staff).
3. **Authentication** > Users > **Add user**. This is the demo staff account, for example `pharmacist@demo.clinic` with a password of your choice.
4. **Firestore Database** > Create database (any region, production mode). Then open **Rules**, paste the contents of `firestore.rules` and click **Publish**. Paste them again whenever `firestore.rules` changes. The latest version lets patients acknowledge urgent instructions.

Then, in this folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup_firebase.ps1
```

The script does four things:

1. Adds the web platform.
2. Adds the Firebase packages.
3. Logs you in to Firebase.
4. Runs `flutterfire configure`, which creates `lib/firebase_options.dart`. Pick your project and Android + web when asked.

When it finishes, run either part:

```powershell
flutter run                                          # patient app on the phone
flutter run -d chrome -t lib/portal/main_portal.dart  # clinician portal
```

## Demo script: patient to clinician and back

1. **Phone:** sign in as Amina. Go to **Report**, pick Hand-foot pain, choose Moderate, and send.
2. **Portal:** the report appears under **Side effects**. Open it, type a reply and press **Send reply · Reviewed**.
3. **Phone:** under **History**, the report now shows "Reviewed by your care team" and the reply.
4. **Portal:** press **Confirm ADR**, then **Forward to PPB**. A copyable PPB summary opens. It identifies the patient by initials only.
5. **Phone:** under **Drugs** > "Tell us about another medicine", search `St` and pick **St John's wort**. (Log in as John Kamau, who takes imatinib, to see an interaction.)
6. **Portal:** under **Medicine checks** the pharmacist sees the interaction warning. Approve it, or flag it with a note. The phone updates a few seconds later.
7. **Portal:** **Patients** shows each patient's dose log as a 14-day bar chart, with an alert after 3 misses in a row.
8. **Urgent care:** open a severe report and choose an action: call the patient, come to clinic today, go to emergency now, or request an ambulance. The phone rings with a full-screen instruction. When the patient taps **I understand**, the portal shows "Patient acknowledged". The ambulance option is a demo and isn't connected to any dispatch service.
9. **Prescription change:** under **Patients** > **Prescription**, add a medicine, for example ondansetron, 1 tablet (8 mg) at 08:00 and 20:00, every day. Then click Save. Within seconds the phone shows "Your care team updated your prescription", and the new doses appear and get alarms.
10. **Messages:** on the phone, go to **Drugs** > **Ask a pharmacist** and send a question. It appears under **Messages** in the portal, with a "Reply" tag. Replies show on the phone straight away.
11. **Several patients:** on the phone, tap the account icon on Today > **Sign out**, then sign in as John Kamau. The portal lists both patients.

If the phone is offline, everything still saves on the phone and shows "waiting to sync". It sends as soon as the connection is back.

## Sharing the demo: APK + portal link

```powershell
powershell -ExecutionPolicy Bypass -File .\release.ps1
```

The script does four things:

1. Builds the patient app as `release\angies-app.apk`. Send it to anyone with an Android phone; they need to allow "install unknown apps".
2. Builds the clinician portal for the web.
3. Publishes `firestore.rules` for you, so you no longer need to paste them into the console.
4. Puts the portal online at **https://pharmavigilance.web.app**.

Staff then sign in there with the accounts made by `create_staff.ps1`.

Run it again whenever the code changes. The phone app can't be updated remotely, so send people the new APK.

## Drug library (portal)

Under **Drug library**, staff write the patient-friendly description of a medicine: what it's for, how to take it, side effects and when to get help. The page lists medicines patients take that have no description yet, so staff know where to start. Saved text appears on the patient's Drugs page within seconds, and the phone keeps a copy for offline use. Portal text replaces the bundled sample text in `drugs.json`.

## Demo accounts (mock hospital)

| Patient number | Phone | Patient | Medicine |
| --- | --- | --- | --- |
| ONC-104517 | 0712 345 678 | Amina Wanjiru | Capecitabine 3 tablets, 8 AM and 8 PM, 14 days on / 7 off (today is day 5). Also takes warfarin, which triggers the interaction alert. |
| ONC-200318 | 0733 456 789 | John Kamau | Imatinib 400 mg once a day, 9 AM, no break |

The SMS code is always **123456**. The app shows it on screen because no SMS is sent in the demo.

## How the offline reminders work

- After sign-in, the app turns the prescription into dose times and arms the next 7 days of alarms with Android's `AlarmManager` (via the [`alarm`](https://pub.dev/packages/alarm) package). Android stores the alarms itself, so they ring with no internet, with the app closed, and after a reboot.
- Every time the app opens, it re-arms the next 7 days, so the schedule keeps rolling.
- When a dose is due:
    1. The alarm rings full screen until the patient taps **Taken**, **Snooze 10 min** or **Missed**. **Missed** asks for a reason.
    2. If there's no answer, it rings again 15 minutes later.
    3. After 30 minutes, the dose is logged as "no response" and a caregiver alert is queued (only if the patient consented).
- Doses, side effect reports and reported medicines are saved on the phone and marked "waiting to sync" until they reach Firebase.
- For privacy, alarm notifications show the drug name only, never the diagnosis.

For the presentation, use **Demo: ring a test alarm in 1 minute** on the Today screen.

## Code map

```
lib/
  main.dart                  starts the alarm plugin, loads data, runs the app
  app.dart                   app shell; opens the alarm screen when an alarm rings
  app_scope.dart             shares services with every screen
  models/models.dart         Patient, Prescription, DoseEvent, AdrReport...
  data/local_store.dart      on-phone storage (offline first)
  data/mock_hospital_api.dart  stand-in for the hospital/pharmacy system
  data/drug_library.dart     bundled drug info + interaction checks
  services/schedule_service.dart  prescription -> dose times (handles cycles)
  services/alarm_service.dart     arms/stops alarms, snooze, escalation
  services/permission_service.dart  notifications, exact alarms, battery
  services/sync_service.dart  sends reports/doses/medicines to Firebase, gets replies back
  portal/                    clinician web portal (side effects, medicine checks, adherence)
  l10n/strings.dart          English + Kiswahili text
  screens/                   sign-in, OTP, confirm details, permissions,
                             today, alarm, report, drug info, history
assets/data/                 drugs.json, interactions.json, medicines.json (SAMPLE data)
tools/ddinter_import.py      builds the medicine list + interactions from DDInter CSVs
firestore.rules              Firestore security rules (demo)
```

## Must be checked before real use

- **Drug info and interactions** (`assets/data/`) are sample content. The pharmacy students must review it, and the interaction list should be replaced with a DDInter 2.0 subset. DDInter's licence is non-commercial.
- **Kiswahili text** (`lib/l10n/strings.dart`) is a first draft. Have a fluent speaker check it.
- **Emergency wording** on the severe-reaction dialog needs clinician approval.

## Drug search and DDInter

The search list (`assets/data/medicines.json`, about 1,970 names) combines two sources:

- A starter list of common medicines, with Kenyan brand names mapped to their ingredients. For example, Mara Moja is checked as paracetamol + aspirin + caffeine.
- Every drug name in DDInter 2.0.

`assets/data/interactions.json` holds about 6,950 moderate or major interactions between 24 oral cancer drugs and everything else, from DDInter 2.0. A few hand-written entries with clearer wording come first. DDInter uses US names, so the import also maps acetaminophen to paracetamol and acetylsalicylic acid to aspirin.

To refresh from a new DDInter export, put `ddinter_compact.txt` in this folder and run `python tools/apply_ddinter_compact.py`. (Or put the 8 original CSV files in `tools/ddinter/` and run `python tools/ddinter_import.py`.)

DDInter is licensed CC BY-NC-SA 4.0. It's fine for this non-commercial project, with credit, but not for a commercial release.

## Known limits

- Patient sign-in and SMS codes are still mocked (`MockHospitalApi`). Patients use anonymous Firebase sign-in behind the scenes.
- The security rules are demo-grade. See the comment at the top of `firestore.rules` for the gap and how to close it.
- "No response" is detected when the app next opens. A Cloud Function could do it in real time.
- Urgent instructions and prescription changes reach the phone while the app is open or in the background. If the app has been fully closed, they arrive the next time it opens. Real use needs push notifications (Firebase Cloud Messaging plus a Cloud Function).
- The ambulance request only records the request and tells the patient. It isn't connected to a dispatch service, and the app doesn't share the patient's location.
- The local brand names in `medicines.json` (for example Mara Moja) and their ingredients must be checked by the pharmacy students.
- Not built yet: caregiver SMS, the PIN/fingerprint lock, photo upload, shared-phone profiles and iOS.

## Next

1. Real hospital API instead of `MockHospitalApi`, and Firebase phone-number sign-in.
2. Cloud Functions: real-time escalation, caregiver SMS, and custom claims for tighter rules.
3. A direct PPB submission, if the PPB accepts reports from third-party systems.
