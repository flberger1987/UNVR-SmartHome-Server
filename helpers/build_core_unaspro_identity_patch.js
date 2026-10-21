'use strict';

const crypto = require('crypto');
const fs = require('fs');

const [sourcePath, outputPath] = process.argv.slice(2);
if (!sourcePath || !outputPath) {
  throw new Error('usage: node build_core_unaspro_identity_patch.js SOURCE OUTPUT');
}

const expectedSourceHash = 'f89f57e204ea53024b604b3acbd277fcac03605e7c41ff5d434b433d72f971aa';
const source = fs.readFileSync(sourcePath, 'utf8');
const sourceHash = crypto.createHash('sha256').update(source).digest('hex');
if (sourceHash !== expectedSourceHash) {
  throw new Error(`unexpected Core source hash: ${sourceHash}`);
}

function replaceExactlyOnce(text, needle, replacement, label) {
  const first = text.indexOf(needle);
  if (first === -1 || text.indexOf(needle, first + needle.length) !== -1) {
    throw new Error(`${label} needle did not occur exactly once`);
  }
  return text.slice(0, first) + replacement + text.slice(first + needle.length);
}

const identityNeedle =
  'case"UNASSTU":e.bom?.startsWith("113-04338-")&&(e.shortname="UNASSTU-BK");break}let r=""';
const identityReplacement =
  'case"UNASSTU":e.bom?.startsWith("113-04338-")&&(e.shortname="UNASSTU-BK");break}e.shortname="UNASPRO",e.name="UniFi Network Attached Storage Pro",e.sysid=59985;let r=""';

const updaterNeedle = 'await u0("ubnt-systool",["fwupdate",e])';
const updaterReplacement = 'await u0("/data/unvr-unas-runtime/guarded-fwupdate",[e])';

// A firmware bearer token is bound to the console's existing cloud product.
// Until a converted console has been removed and re-adopted, that token causes
// the service to return the UNVR feed even when Core correctly requests
// product=unifi-drive/platform=UNASPRO. Official release metadata is public,
// so omit the stale product-bound token only for the UNAS release request.
const feedIdentityNeedle = 'let{shortname:o}=x(),a=yi(),n=We()||"release"';
const feedIdentityReplacement =
  'let{shortname:o}=x(),a=o==="UNASPRO"?"unifi-drive":yi(),n=We()||"release"';

const latestFeedNeedle =
  'let c={},p=e||await Fm();p&&(c.headers={Authorization:`Bearer token:${p}`});let u=await oE(`${s}${i}`,c)';
const latestFeedReplacement =
  'let c={},p=o==="UNASPRO"&&n==="release"?null:e||await Fm();p&&(c.headers={Authorization:`Bearer token:${p}`});let u=await oE(`${s}${i}`,c)';

const feedLogNeedle = 'aN.info(`Checking firmware updates for "${n}" channel`);';
const feedLogReplacement =
  'aN.info(`Checking firmware updates for "${n}" channel product="${a}" platform="${o}" query="${i}"`);';

const versionFeedNeedle =
  'let i={};o=o||await Fm(),o&&(i.headers={Authorization:`Bearer token:${o}`});let p=await(await oE(`${n}${s}`,i)).json()';
const versionFeedReplacement =
  'let i={};o=r==="unifi-drive"?null:o||await Fm(),o&&(i.headers={Authorization:`Bearer token:${o}`});let p=await(await oE(`${n}${s}`,i)).json()';

const startupRefreshNeedle =
  't().catch(n=>qf.error("Failed to update applications on startup:",n)),z3().catch(n=>qf.error(\'Failed to send "firmware_update_check" trace event:\',n));';
const startupRefreshReplacement =
  't().catch(n=>qf.error("Failed to update applications on startup:",n)),co(null,{triggeredBy:"system"}).catch(n=>qf.error("Failed to refresh firmware on startup:",n)),z3().catch(n=>qf.error(\'Failed to send "firmware_update_check" trace event:\',n));';

const cachedFeedNeedle = 'S=bB(n),g=Io(m)';
const cachedFeedReplacement =
  'S=(e=>e&&e.product===a&&e.platform===o?e:null)(bB(n)),g=Io(m)';

// Core 4.1 emitted "health" for the protobuf HEALTHY enum. The official UNAS
// portal consumes the 5.x spelling, "healthy", and rejects the legacy value.
// Normalize only this one enum mapper; RAID state and problem mappings remain
// untouched.
const spaceHealthyNeedle =
  'case Tt.SpaceHealthState.SPACE_HEALTH_STATE_HEALTHY:return "health";case Tt.SpaceHealthState.SPACE_HEALTH_STATE_READ_ONLY:';
const spaceHealthyReplacement =
  'case Tt.SpaceHealthState.SPACE_HEALTH_STATE_HEALTHY:return "healthy";case Tt.SpaceHealthState.SPACE_HEALTH_STATE_READ_ONLY:';

let output = replaceExactlyOnce(source, identityNeedle, identityReplacement, 'Core hardware identity');
output = replaceExactlyOnce(output, updaterNeedle, updaterReplacement, 'firmware application boundary');
output = replaceExactlyOnce(output, feedIdentityNeedle, feedIdentityReplacement, 'firmware feed identity');
output = replaceExactlyOnce(output, feedLogNeedle, feedLogReplacement, 'firmware feed diagnostic');
output = replaceExactlyOnce(output, latestFeedNeedle, latestFeedReplacement, 'latest firmware feed authentication');
output = replaceExactlyOnce(output, versionFeedNeedle, versionFeedReplacement, 'specific firmware feed authentication');
output = replaceExactlyOnce(output, startupRefreshNeedle, startupRefreshReplacement, 'startup firmware refresh');
output = replaceExactlyOnce(output, cachedFeedNeedle, cachedFeedReplacement, 'firmware cache identity filter');
output = replaceExactlyOnce(output, spaceHealthyNeedle, spaceHealthyReplacement, 'Core 4.1 storage health mapper');

if (!output.includes('case"UNASPRO":return Ok')) {
  throw new Error('UNASPRO Core profile is missing');
}
if (!output.includes('firmware:{product:"unifi-drive"}')) {
  throw new Error('UNAS firmware catalogue identity is missing');
}
if (!output.includes('features:{adoptableViaDiscovery:!0,clientNetworkConfig:!0,cloudBackup:!0,cpuInfo:!0,hasLCM:!0')) {
  throw new Error('original UNAS Pro LCM capability is missing');
}
if (!output.includes('e.shortname="UNASPRO"')) {
  throw new Error('UNASPRO hardware override is missing');
}
if (!output.includes('/data/unvr-unas-runtime/guarded-fwupdate')) {
  throw new Error('guarded updater boundary is missing');
}
if (!output.includes('a=o==="UNASPRO"?"unifi-drive":yi()')) {
  throw new Error('explicit UNAS release-feed identity is missing');
}
if (!output.includes('p=o==="UNASPRO"&&n==="release"?null:')) {
  throw new Error('public UNAS latest-release token boundary is missing');
}
if (!output.includes('o=r==="unifi-drive"?null:')) {
  throw new Error('public UNAS version-feed boundary is missing');
}
if (!output.includes('co(null,{triggeredBy:"system"})')) {
  throw new Error('startup firmware refresh is missing');
}
if (!output.includes('e.product===a&&e.platform===o')) {
  throw new Error('firmware cache identity filter is missing');
}
if (!output.includes('SPACE_HEALTH_STATE_HEALTHY:return "healthy"')) {
  throw new Error('UNAS storage health normalization is missing');
}

fs.writeFileSync(outputPath, output, { mode: 0o644 });
const outputHash = crypto.createHash('sha256').update(output).digest('hex');
process.stdout.write(`${outputHash}  ${outputPath}\n`);
