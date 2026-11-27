#!/usr/bin/env bash
# Fail the APK release before publication if Android cannot install and launch it.
# Called by the Android-emulator-runner action after flutter build apk --release.
set -euo pipefail

apk="app/build/app/outputs/flutter-apk/app-release.apk"
package="com.shiaai.app"
activity="$package/.MainActivity"

if [[ ! -s "$apk" ]]; then
  echo "::error title=Missing APK::$apk does not exist"
  exit 1
fi

# Check the entire supported Android range, not only the CI emulator's API.
apksigner=$(find "$ANDROID_HOME/build-tools" -maxdepth 2 -type f -name apksigner | sort -V | tail -1)
if [[ -z "$apksigner" ]]; then
  echo '::error title=Missing Android SDK signer::Cannot verify APK signing'
  exit 1
fi
"$apksigner" verify --verbose --print-certs --min-sdk-version 24 "$apk"

echo "Emulator API: $(adb shell getprop ro.build.version.sdk | tr -d '\r')"
echo "Emulator ABI: $(adb shell getprop ro.product.cpu.abi | tr -d '\r')"

# Isolate any regression from the previous release. A failure on the old APK
# is diagnostic, not a pass for the new one. Also check upgrade compatibility.
mkdir -p build/install-smoke
if gh release download app-v1.13.0 -p 'ShiaVerse-1.13.0.apk' -D build/install-smoke --clobber; then
  old=build/install-smoke/ShiaVerse-1.13.0.apk
  echo "Previous release SHA-256: $(sha256sum "$old" | cut -d' ' -f1)"
  if adb install --no-streaming "$old"; then
    echo 'Previous release installed on emulator; trying an in-place update.'
    if ! adb install -r --no-streaming "$apk"; then
      echo '::warning title=APK update failed::Could be different release signing keys; clean install is checked separately.'
    fi
  else
    echo '::warning title=Previous APK would not install on emulator::See the adb failure above.'
  fi
else
  echo '::warning title=Previous APK not downloaded::Only the new APK will be tested.'
fi

# A clean install is mandatory regardless of how the previous-release test went.
adb uninstall "$package" || true
printf '\nInstalling the NEW signed release APK on a clean Android emulator...\n'
adb install --no-streaming "$apk"
if ! adb shell pm path "$package" | grep -q 'base.apk'; then
  echo '::error title=APK installation failed::The package manager cannot find the installed APK'
  exit 1
fi

launch=$(adb shell am start -W -n "$activity" 2>&1)
echo "$launch"
if grep -Eq 'Error:|Exception|unable to resolve' <<< "$launch"; then
  echo '::error title=App launch failed::Android rejected the main activity'
  exit 1
fi

# am start can report success just before Flutter crashes or shows a bootstrap
# error; wait for bundled DB extraction and confirm both PID and installed DBs.
sleep 8
if ! adb shell pidof "$package" | grep -Eq '[0-9]+'; then
  adb logcat -d -t 200 -s AndroidRuntime:E ActivityTaskManager:E flutter:E || true
  echo '::error title=App launch failed::Process exited during startup'
  exit 1
fi
if adb logcat -d -s flutter:E flutter:I | grep -Eq 'Bundled database checksum|Bad state:'; then
  adb logcat -d -t 200 -s flutter:E flutter:I || true
  echo '::error title=Flutter bootstrap error::Startup logged a Bad state / checksum error'
  exit 1
fi

# The release also ships one APK per CPU for slow connections. Install the
# x86_64 split over the universal build to prove those files are valid too.
split=app/build/app/outputs/flutter-apk/app-x86_64-release.apk
if [[ -f "$split" ]]; then
  printf '\nInstalling the x86_64 split APK (same version, same signer)...\n'
  adb install -r --no-streaming "$split"
  if ! adb shell pm path "$package" | grep -q 'base.apk'; then
    echo '::error title=Split APK installation failed::the package manager rejected the per-ABI APK'
    exit 1
  fi
  echo 'Per-ABI APK installed over the universal build.'
fi

echo 'Android emulator clean install AND launch verified.'
