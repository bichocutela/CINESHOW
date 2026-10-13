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
