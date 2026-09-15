const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { metadata, expectedAssets, collectApks, checksums, restoreKeystore } = require('./release.cjs');

test('release tags produce matching app, Windows and prerelease metadata', () => {
  assert.deepEqual(metadata('v1.2.3', '12'), {
    tag: 'v1.2.3', version: '1.2.3', build_number: '12', windows_version: '1.2.3.12', prerelease: 'false',
  });
  assert.equal(metadata('v2.0.0-rc.1', 13).prerelease, 'true');
  assert.equal(metadata('v2.0.0-rc.1', 13).windows_version, '2.0.0.13');
  for (const tag of ['main', '1.2.3', 'v01.2.3', 'v1.2.3-01', 'v1.2.3\n', 'v1.2.3;echo bad', 'v65536.0.0']) {
    assert.throws(() => metadata(tag, 1));
  }
  for (const build of [0, -1, '1.5', 65536]) assert.throws(() => metadata('v1.0.0', build));
});

test('release assembly rejects missing assets and writes verifiable checksums', t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'minireel-release-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const source = path.join(directory, 'apks');
  const release = path.join(directory, 'release');
  fs.mkdirSync(source);
  for (const flavor of ['phone', 'tv']) {
    for (const abi of ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
      fs.writeFileSync(path.join(source, `app-${abi}-${flavor}-release.apk`), `signed ${flavor} ${abi}`);
    }
  }
  collectApks('1.2.3', source, release, 'phone');
  assert.throws(() => checksums('1.2.3', release), /exactly/);
  fs.writeFileSync(path.join(release, 'MiniReel-1.2.3-windows-x64-setup.exe'), 'installer');
  assert.throws(() => checksums('1.2.3', release), /exactly/);
  collectApks('1.2.3', source, release, 'tv');
  for (const abi of ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
    assert.equal(fs.readFileSync(path.join(release, `MiniReel-1.2.3-android-${abi}.apk`), 'utf8'), `signed phone ${abi}`);
    assert.equal(fs.readFileSync(path.join(release, `MiniReel-1.2.3-android-tv-${abi}.apk`), 'utf8'), `signed tv ${abi}`);
  }
  checksums('1.2.3', release);
  const entries = fs.readFileSync(path.join(release, 'SHA256SUMS.txt'), 'utf8').trim().split('\n');
  assert.equal(entries.length, 7);
  assert.deepEqual(entries.map(line => line.split('  ')[1]), expectedAssets('1.2.3'));
  for (const line of entries) {
    const [digest, name] = line.split('  ');
    assert.equal(digest, crypto.createHash('sha256').update(fs.readFileSync(path.join(release, name))).digest('hex'));
  }
  fs.writeFileSync(path.join(release, 'unexpected.txt'), 'extra');
  assert.throws(() => checksums('1.2.3', release), /exactly/);
});

test('APK collection rejects missing, empty and unspecified flavors', t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'minireel-apk-test-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const destination = path.join(directory, 'release');
  for (const flavor of [undefined, '', 'desktop', '../tv']) {
    assert.throws(() => collectApks('1.2.3', directory, destination, flavor), /flavor/);
  }
  for (const flavor of ['phone', 'tv']) {
    assert.throws(() => collectApks('1.2.3', directory, destination, flavor), /Missing or empty/);
    fs.writeFileSync(path.join(directory, `app-arm64-v8a-${flavor}-release.apk`), '');
    assert.throws(() => collectApks('1.2.3', directory, destination, flavor), /Missing or empty/);
  }
});

test('signing restore fails closed on missing or malformed secrets and never replaces a key', t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'minireel-signing-test-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const file = path.join(directory, 'test.jks');
  const bytes = Buffer.alloc(80, 42);
  const environment = {
    ANDROID_KEYSTORE_BASE64: bytes.toString('base64'),
    ANDROID_KEYSTORE_PASSWORD: 'synthetic-store-password',
    ANDROID_KEY_ALIAS: 'synthetic-alias',
    ANDROID_KEY_PASSWORD: 'synthetic-key-password',
  };
  assert.throws(() => restoreKeystore(file, {}), /Missing repository secret/);
  assert.equal(fs.existsSync(file), false);
  assert.throws(() => restoreKeystore(file, { ...environment, ANDROID_KEYSTORE_BASE64: 'not base64!' }), /valid Base64/);
  restoreKeystore(file, environment);
  assert.deepEqual(fs.readFileSync(file), bytes);
  assert.throws(() => restoreKeystore(file, environment), /EEXIST/);
});
