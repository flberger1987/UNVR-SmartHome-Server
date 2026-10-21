'use strict';

// Build the exact scoped identity/update-boundary patch for the matched pair:
// physical UNVR 5.1.x base + logical original UNAS Pro 5.1.x userspace.

const crypto = require('crypto');
const fs = require('fs');

const [sourcePath, outputPath, logicalVersion = '5.1.32'] = process.argv.slice(2);
if (!sourcePath || !outputPath) {
  throw new Error('usage: node build_core_5x_unaspro_patch.js SOURCE OUTPUT [4.3.10|5.1.32|5.1.33]');
}
if (!new Set(['4.3.10', '5.1.32', '5.1.33']).has(logicalVersion)) {
  throw new Error(`unsupported logical UNAS version: ${logicalVersion}`);
}

const expectedSourceHash = '9def42c03b368a9434b1b3d5ee48f7a295bae616ae1060639f4c53c4e292fbb0';
const source = fs.readFileSync(sourcePath, 'utf8');
const sourceHash = crypto.createHash('sha256').update(source).digest('hex');
if (sourceHash !== expectedSourceHash) {
  throw new Error(`unexpected Core 5.1.132 source hash: ${sourceHash}`);
}

function replaceExactlyOnce(text, needle, replacement, label) {
  const first = text.indexOf(needle);
  if (first === -1 || text.indexOf(needle, first + needle.length) !== -1) {
    throw new Error(`${label} needle did not occur exactly once`);
  }
  return text.slice(0, first) + replacement + text.slice(first + needle.length);
}

const identityNeedle = 'case "uuid":e[s]=c;break}}});let r="";try';
const identityReplacement =
  'case "uuid":e[s]=c;break}}});e.shortname="UNASPRO",e.name="UniFi Network Attached Storage Pro",e.sysid=59985;let r="";try';

const logicalVersionNeedle =
  'let n=q_(r);e.firmwareVersion=n,aRe.info(`Full firmware version string: ${r}`);';
const logicalVersionReplacement =
  `let n=q_(r);e.firmwareVersion=${JSON.stringify(logicalVersion)},aRe.info(\`Full firmware version string: \${r}; logical UNAS version: ${logicalVersion}\`);`;

const updaterNeedle = 'await DM("ubnt-systool",["fwupdate",e])';
const updaterReplacement = 'await DM("/data/unvr-unas-runtime/guarded-fwupdate",[e])';

const feedIdentityNeedle = 'let o=await tl(),n=el(),a=Sr()||"release"';
const feedIdentityReplacement =
  'let o=await tl(),n=o==="UNASPRO"?"unifi-drive":el(),a=Sr()||"release"';

const latestFeedNeedle =
  'let c={},p=e||await fd();p&&(c.headers={Authorization:`Bearer token:${p}`});let u=await Hr(`${i}${s}`,c)';
const latestFeedReplacement =
  'let c={},p=o==="UNASPRO"&&a==="release"?null:e||await fd();p&&(c.headers={Authorization:`Bearer token:${p}`});let u=await Hr(`${i}${s}`,c)';

const feedLogNeedle = 'LG.info(`Checking firmware updates for "${a}" channel`);';
const feedLogReplacement =
  'LG.info(`Checking firmware updates for "${a}" channel product="${n}" platform="${o}" query="${s}"`);';

const versionFeedNeedle =
  'let s={};o=o||await fd(),o&&(s.headers={Authorization:`Bearer token:${o}`});let p=await(await Hr(`${a}${i}`,s)).json()';
const versionFeedReplacement =
  'let s={};o=r==="unifi-drive"?null:o||await fd(),o&&(s.headers={Authorization:`Bearer token:${o}`});let p=await(await Hr(`${a}${i}`,s)).json()';

const cachedFeedNeedle = 'y=WQ(a),g=Xn(f)';
const cachedFeedReplacement =
  'y=(e=>e&&e.product===n&&e.platform===o?e:null)(WQ(a)),g=Xn(f)';

const startupRefreshNeedle =
  'Age().catch(i=>em.error("Failed to handle firmware updating state:",i)),yge().catch(i=>em.error(\'Failed to send "firmware_update_check" trace event:\',i));';
const startupRefreshReplacement =
  'Age().catch(i=>em.error("Failed to handle firmware updating state:",i)),bn(null,{triggeredBy:"system"}).catch(i=>em.error("Failed to refresh firmware on startup:",i)),yge().catch(i=>em.error(\'Failed to send "firmware_update_check" trace event:\',i));';

let output = replaceExactlyOnce(source, identityNeedle, identityReplacement, 'Core 5.x hardware identity');
output = replaceExactlyOnce(output, logicalVersionNeedle, logicalVersionReplacement, 'Core 5.x logical firmware version');
output = replaceExactlyOnce(output, updaterNeedle, updaterReplacement, 'Core 5.x firmware application boundary');
output = replaceExactlyOnce(output, feedIdentityNeedle, feedIdentityReplacement, 'Core 5.x firmware feed identity');
output = replaceExactlyOnce(output, feedLogNeedle, feedLogReplacement, 'Core 5.x firmware feed diagnostic');
output = replaceExactlyOnce(output, latestFeedNeedle, latestFeedReplacement, 'Core 5.x latest firmware feed authentication');
output = replaceExactlyOnce(output, versionFeedNeedle, versionFeedReplacement, 'Core 5.x specific firmware feed authentication');
output = replaceExactlyOnce(output, cachedFeedNeedle, cachedFeedReplacement, 'Core 5.x firmware cache identity filter');
output = replaceExactlyOnce(output, startupRefreshNeedle, startupRefreshReplacement, 'Core 5.x startup firmware refresh');

// The converted console supports explicit, guarded OS updates, not the
// automatic firmware action embedded in native first-time setup. Enforce the
// existing no-auto-updates policy at the native schedule setters so setup,
// site merge, backup restore and later API calls cannot reinstate a schedule.
// Manual firmware/application update functions are deliberately unchanged.
if (logicalVersion !== '4.3.10') {
  output = replaceExactlyOnce(output, 'let F=await o5e(r,y);',
    'let F=false;', 'skip setup-triggered firmware installation');
  output = replaceExactlyOnce(output,
    'function Us({schedule:e,includeApplications:t}){',
    'function Us({schedule:e,includeApplications:t}){e=null,t=false;',
    'disable automatic firmware schedules');
  output = replaceExactlyOnce(output, 'function Oie(){let e=bs();',
    'function Oie(){Us({schedule:null,includeApplications:false});let e=bs();',
    'clear persisted firmware schedules before startup');
  output = replaceExactlyOnce(output, 'function Op(e){let t=Kn();',
    'function Op(e){e=Object.fromEntries([...new Set([...Object.keys(Kn()),...Object.keys(e)])].map(e=>[e,null]));let t=Kn();',
    'disable automatic application schedules');
  output = replaceExactlyOnce(output, 'function zF(){let e=Kn();',
    'function zF(){Op(Kn());let e=Kn();',
    'clear persisted application schedules before startup');
}

const required = [
  'case "UNASPRO":return o2',
  'deviceType:"unas-pro"',
  'firmware:{product:"unifi-drive"}',
  'e.shortname="UNASPRO"',
  `e.firmwareVersion=${JSON.stringify(logicalVersion)}`,
  '/data/unvr-unas-runtime/guarded-fwupdate',
  'n=o==="UNASPRO"?"unifi-drive":el()',
  'p=o==="UNASPRO"&&a==="release"?null:',
  'o=r==="unifi-drive"?null:',
  'e.product===n&&e.platform===o',
  'bn(null,{triggeredBy:"system"})',
];
for (const value of required) {
  if (!output.includes(value)) throw new Error(`required Core 5.x patch invariant is missing: ${value}`);
}

fs.writeFileSync(outputPath, output, { mode: 0o644 });
const outputHash = crypto.createHash('sha256').update(output).digest('hex');
process.stdout.write(`${outputHash}  ${outputPath}\n`);
