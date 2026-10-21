'use strict';

const crypto = require('crypto');
const fs = require('fs');

const [sourcePath, outputPath] = process.argv.slice(2);
if (!sourcePath || !outputPath) {
  throw new Error('usage: node patch_portal_unaspro_manifest.js SOURCE OUTPUT');
}

const expectedSourceHash = '669939632bae4d24ddc0a60e9b6b844c26c8e57888c26e05610c77a122247450';
const source = fs.readFileSync(sourcePath, 'utf8');
const sourceHash = crypto.createHash('sha256').update(source).digest('hex');
if (sourceHash !== expectedSourceHash) {
  throw new Error(`unexpected portal source hash: ${sourceHash}`);
}

const oldManifest =
  'window.UNIFI_OS_MANIFEST = {"model":{"id":"UNVR","shortName":"UNVR","longName":"UniFi Protect Network Video Recorder"},"images":[{"size":1024,"url":"/assets/images/1024.png?unvr-3.0.1"},{"size":64,"url":"/assets/images/64.png?unvr-3.0.1"},{"size":48,"url":"/assets/images/48.png?unvr-3.0.1"}]}';
const newManifest =
  'window.UNIFI_OS_MANIFEST = {"model":{"id":"UNASPRO","shortName":"UNAS Pro","longName":"UniFi Network Attached Storage Pro"},"images":[{"size":1024,"url":"/assets/images/1024.png?unaspro-3.0.2"},{"size":64,"url":"/assets/images/64.png?unaspro-3.0.2"},{"size":48,"url":"/assets/images/48.png?unaspro-3.0.2"}]}';

const first = source.indexOf(oldManifest);
if (first === -1 || source.indexOf(oldManifest, first + oldManifest.length) !== -1) {
  throw new Error('UNVR portal manifest did not occur exactly once');
}

const output = source.slice(0, first) + newManifest + source.slice(first + oldManifest.length);
if (output.includes('window.UNIFI_OS_MANIFEST = {"model":{"id":"UNVR"')) {
  throw new Error('UNVR portal manifest remains after patch');
}

fs.writeFileSync(outputPath, output, { mode: 0o644 });
const outputHash = crypto.createHash('sha256').update(output).digest('hex');
process.stdout.write(`${outputHash}  ${outputPath}\n`);
