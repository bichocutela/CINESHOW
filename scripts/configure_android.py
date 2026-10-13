"""Apply stable package/signing settings to Flutter-generated Android scaffold."""
from pathlib import Path
p=Path('android/app/build.gradle.kts')
s=p.read_text()
# Flutter creates the permanent id from --org=com.bichocutela and project cineshow.
if 'com.bichocutela.cineshow' not in s:
 raise SystemExit('Unexpected Android application id')
s='import java.util.Properties\nimport java.io.FileInputStream\n'+s
s=s.replace('android {','''val signingProperties = Properties()
val signingFile = rootProject.file("key.properties")
if (signingFile.exists()) signingProperties.load(FileInputStream(signingFile))

android {''',1)
s=s.replace('    buildTypes {','''    signingConfigs {
        if (signingFile.exists()) {
            create("release") {
                keyAlias = signingProperties["keyAlias"] as String
                keyPassword = signingProperties["keyPassword"] as String
                storeFile = rootProject.file(signingProperties["storeFile"] as String)
                storePassword = signingProperties["storePassword"] as String
            }
        }
    }
    buildTypes {''',1)
s=s.replace('signingConfig = signingConfigs.getByName("debug")','signingConfig = signingConfigs.getByName(if (signingFile.exists()) "release" else "debug")')
p.write_text(s)
m=Path('android/app/src/main/AndroidManifest.xml');s=m.read_text();s=s.replace('    <application','    <uses-permission android:name="android.permission.INTERNET" />\n    <application',1);s=s.replace('android:label="cineshow"','android:label="CINESHOW"');m.write_text(s)

# Keep the official PNG byte-identical; only the Android container adds safe space.
import shutil
res = Path('android/app/src/main/res')
for directory in ('drawable', 'drawable-anydpi-v26', 'values'):
 (res / directory).mkdir(parents=True, exist_ok=True)
shutil.copyfile('assets/logo_icon.png', res / 'drawable/cineshow_mark.png')
(res / 'values/cineshow_colors.xml').write_text('<resources><color name="cineshow_icon_background">#0B0B10</color></resources>')
(res / 'drawable/cineshow_launcher.xml').write_text('''<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
 <item android:drawable="@color/cineshow_icon_background" />
 <item android:left="4dp" android:top="4dp" android:right="4dp" android:bottom="4dp">
  <bitmap android:src="@drawable/cineshow_mark" android:gravity="fill" android:filter="true" />
 </item>
</layer-list>''')
(res / 'drawable-anydpi-v26/cineshow_launcher.xml').write_text('''<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
 <background android:drawable="@color/cineshow_icon_background" />
 <foreground><inset android:inset="26%">
  <bitmap android:src="@drawable/cineshow_mark" android:gravity="fill" android:filter="true" />
 </inset></foreground>
</adaptive-icon>''')
s=m.read_text().replace('android:icon="@mipmap/ic_launcher"', 'android:icon="@drawable/cineshow_launcher" android:roundIcon="@drawable/cineshow_launcher"')
m.write_text(s)
