# Build the Flutter web app into hosting/app and deploy the whole site.
flutter build web --release --base-href /app/
if (Test-Path hosting\app) { Remove-Item -Recurse -Force hosting\app }
New-Item -ItemType Directory -Force -Path hosting\app | Out-Null
Copy-Item -Recurse -Force build\web\* hosting\app\
Copy-Item -Force web\firebase-messaging-sw.js hosting\firebase-messaging-sw.js

# Publish the latest release APK for download from the landing page.
if (Test-Path build\app\outputs\flutter-apk\app-release.apk) {
  New-Item -ItemType Directory -Force -Path hosting\downloads | Out-Null
  Copy-Item -Force build\app\outputs\flutter-apk\app-release.apk hosting\downloads\StaffConnect.apk
}

firebase deploy --only hosting
