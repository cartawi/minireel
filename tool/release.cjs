const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

function metadata(tag, buildNumber) {
  const match = /^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/.exec(tag || '');
  if (!match || match[0] !== tag) throw new Error('Use a version tag such as v0.1.0 or v0.2.0-beta.1.');
  if (match.slice(1, 4).some(value => Number(value) > 65535)) {
    throw new Error('Version components must fit the Windows version resource (0–65535).');
  }
  if (match[4]?.split('.').some(value => /^0\d+$/.test(value))) {
    throw new Error('Numeric prerelease identifiers cannot have leading zeroes.');
  }
  if (!/^[1-9]\d*$/.test(String(buildNumber)) || Number(buildNumber) > 65535) {
    throw new Error('Build number must be an integer from 1 to 65535.');
  }
  return {
    tag,
    version: tag.slice(1),
    build_number: String(buildNumber),
    windows_version: `${match[1]}.${match[2]}.${match[3]}.${buildNumber}`,
    prerelease: String(Boolean(match[4])),
  };
}

const androidAbis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
const androidFlavors = ['phone', 'tv'];

function apkAsset(version, abi, flavor) {
  return `MiniReel-${version}-android${flavor === 'tv' ? '-tv' : ''}-${abi}.apk`;
}

function expectedAssets(version) {
  return [
    `MiniReel-${version}-windows-x64-setup.exe`,
    ...androidFlavors.flatMap(flavor => androidAbis.map(abi => apkAsset(version, abi, flavor))),
  ].sort();
}

function collectApks(version, source, destination, flavor) {
  metadata(`v${version}`, 1);
  if (!androidFlavors.includes(flavor)) throw new Error('APK flavor must be phone or tv.');
  fs.mkdirSync(destination, { recursive: true });
  for (const abi of androidAbis) {
    const input = path.join(source, `app-${flavor}-${abi}-release.apk`);
    if (!fs.existsSync(input) || !fs.statSync(input).isFile() || fs.statSync(input).size === 0) {
      throw new Error(`Missing or empty APK for ${flavor}/${abi}.`);
    }
    fs.copyFileSync(input, path.join(destination, apkAsset(version, abi, flavor)));
  }
}

function checksums(version, directory) {
  metadata(`v${version}`, 1);
  const expected = expectedAssets(version);
  const actual = fs.readdirSync(directory).filter(name => name !== 'SHA256SUMS.txt').sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`Release must contain exactly the Windows installer and six APKs (three phone, three TV). Found: ${actual.join(', ')}`);
  }
  const lines = expected.map(name => {
    const bytes = fs.readFileSync(path.join(directory, name));
    if (bytes.length === 0) throw new Error(`Empty release asset: ${name}`);
    return `${crypto.createHash('sha256').update(bytes).digest('hex')}  ${name}`;
  });
  fs.writeFileSync(path.join(directory, 'SHA256SUMS.txt'), `${lines.join('\n')}\n`);
}

function restoreKeystore(destination, environment = process.env) {
  const names = ['ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD'];
  for (const name of names) {
    if (!environment[name]) throw new Error(`Missing repository secret: ${name}`);
  }
  const encoded = environment.ANDROID_KEYSTORE_BASE64.replace(/\s/g, '');
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded)) {
    throw new Error('ANDROID_KEYSTORE_BASE64 is not valid Base64.');
  }
  const bytes = Buffer.from(encoded, 'base64');
  if (bytes.length < 64) throw new Error('The signing keystore is empty or incomplete.');
  fs.writeFileSync(destination, bytes, { mode: 0o600, flag: 'wx' });
}

if (require.main === module) {
  try {
    const [command, ...args] = process.argv.slice(2);
    if (command === 'metadata') {
      const values = metadata(process.env.RELEASE_TAG, process.env.RELEASE_BUILD_NUMBER);
      if (process.env.GITHUB_OUTPUT) {
        fs.appendFileSync(process.env.GITHUB_OUTPUT, Object.entries(values).map(([key, value]) => `${key}=${value}\n`).join(''));
      }
      console.log(JSON.stringify(values));
    } else if (command === 'collect-apks') {
      collectApks(...args);
    } else if (command === 'checksums') {
      checksums(...args);
    } else if (command === 'restore-keystore') {
      restoreKeystore(args[0]);
      console.log('Android signing keystore restored.');
    } else {
      throw new Error('Expected metadata, collect-apks, checksums, or restore-keystore.');
    }
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = { metadata, expectedAssets, collectApks, checksums, restoreKeystore };
