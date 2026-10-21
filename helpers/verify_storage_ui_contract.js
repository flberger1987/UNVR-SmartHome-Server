'use strict';

// Offline verifier for the Core -> UniFi Portal storage-health contract.
// The 4.1 UNAS portal accepts `healthy`, while the unmodified 4.1 Core mapper
// emits the legacy value `health`. A converted profile must normalize that
// boundary or the Control Plane Storage tab throws during rendering.

const fs = require('fs');
const path = require('path');

const [corePath, portalPath] = process.argv.slice(2);
if (!corePath || !portalPath) {
  throw new Error('usage: node verify_storage_ui_contract.js CORE_JS PORTAL_JS_OR_DIRECTORY');
}

function readPortal(target) {
  const stat = fs.statSync(target);
  if (stat.isFile()) return fs.readFileSync(target, 'utf8');
  const files = fs.readdirSync(target)
    .filter((name) => name.endsWith('.js'))
    .sort();
  if (files.length === 0) throw new Error(`no portal JavaScript found in ${target}`);
  return files.map((name) => fs.readFileSync(path.join(target, name), 'utf8')).join('\n');
}

const core = fs.readFileSync(corePath, 'utf8');
const portal = readPortal(portalPath);

const mapperPatterns = [
  /SpaceHealthState\.SPACE_HEALTH_STATE_HEALTHY:return\s*"([^"]+)"/,
  /SpaceState\.SPACE_STATE_HEALTHY:return\s*"([^"]+)"/,
];
const mapper = mapperPatterns.map((pattern) => core.match(pattern)).find(Boolean);
if (!mapper) throw new Error('could not locate the Core healthy-space mapper');

const mappedValue = mapper[1];
const portalAcceptsHealthy = portal.includes('case"healthy"');
const portalAcceptsLegacyHealth = portal.includes('case"health"');

if (!portalAcceptsHealthy) throw new Error('portal does not contain the expected healthy-space state');
if (mappedValue !== 'healthy') {
  throw new Error(
    `storage UI contract mismatch: Core emits ${JSON.stringify(mappedValue)}, portal expects "healthy"`,
  );
}

process.stdout.write(JSON.stringify({
  coreHealthyState: mappedValue,
  portalAcceptsHealthy,
  portalAcceptsLegacyHealth,
  compatible: true,
}) + '\n');
