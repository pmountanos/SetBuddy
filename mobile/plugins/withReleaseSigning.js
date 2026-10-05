const { withAppBuildGradle } = require('expo/config-plugins');

/**
 * Signs Android release builds with the project's release keystore — the same key the Kotlin app was released
 * with, so the React Native build installs as an upgrade over it.
 *
 * The keystore and its passwords are not in git: `keystore.properties` at the repo root (two levels above the
 * generated `android/` folder) names the `.jks` file and its credentials. When that file is absent (a fresh
 * checkout), release builds fall back to the debug key so they still build, exactly as before this plugin.
 *
 * `android/` is generated, so this has to be a config plugin rather than a hand edit. Each replacement checks
 * that its anchor exists and fails loudly if a future Expo template changes the file's shape.
 */
function replaceOnce(contents, anchor, replacement, what) {
  const first = contents.indexOf(anchor);
  if (first === -1) throw new Error(`withReleaseSigning: could not find ${what} in android/app/build.gradle`);
  return contents.slice(0, first) + replacement + contents.slice(first + anchor.length);
}

module.exports = function withReleaseSigning(config) {
  return withAppBuildGradle(config, (gradle) => {
    let contents = gradle.modResults.contents;
    if (contents.includes('releaseKeystoreProperties')) return gradle;

    contents = replaceOnce(
      contents,
      'android {',
      `def releaseKeystoreFile = rootProject.file('../../keystore.properties')
def releaseKeystoreProperties = new Properties()
if (releaseKeystoreFile.exists()) {
    releaseKeystoreFile.withInputStream { releaseKeystoreProperties.load(it) }
}

android {`,
      'the android block',
    );

    contents = replaceOnce(
      contents,
      'signingConfigs {',
      `signingConfigs {
        release {
            if (releaseKeystoreFile.exists()) {
                storeFile rootProject.file('../../' + releaseKeystoreProperties['storeFile'])
                storePassword releaseKeystoreProperties['storePassword']
                keyAlias releaseKeystoreProperties['keyAlias']
                keyPassword releaseKeystoreProperties['keyPassword']
            }
        }`,
      'signingConfigs',
    );

    // The template signs both build types with the debug key; only the release type's line changes.
    const releaseBlock = contents.indexOf('release {', contents.indexOf('buildTypes {'));
    if (releaseBlock === -1) throw new Error('withReleaseSigning: could not find the release build type in android/app/build.gradle');
    contents =
      contents.slice(0, releaseBlock) +
      replaceOnce(
        contents.slice(releaseBlock),
        'signingConfig signingConfigs.debug',
        'signingConfig releaseKeystoreFile.exists() ? signingConfigs.release : signingConfigs.debug',
        "the release build type's signingConfig",
      );

    gradle.modResults.contents = contents;
    return gradle;
  });
};
