'use strict';

// One-shot, read-only view of Drive's normalized storage stream.

const grpc = require('/usr/share/unifi-core/app/node_modules/@grpc/grpc-js');
const api = require('/usr/share/unifi-core/app/node_modules/@ubnt/unifi-protobufs/unifi/drive/storage/v1/api_grpc_pb.js');
const messages = require('/usr/share/unifi-core/app/node_modules/@ubnt/unifi-protobufs/unifi/drive/storage/v1/api_pb.js');

function sanitize(value, key = '') {
  const sensitive =
    /(^|_)(id|uuid|serial|mac|token|key)$/i.test(key) ||
    (key !== 'slotId' && /(ids?list|id|uuid|serial|mac|token|key)$/i.test(key));
  if (sensitive) {
    if (Array.isArray(value)) return value.map(() => '[REDACTED]');
    return '[REDACTED]';
  }
  if (Array.isArray(value)) return value.map((child) => sanitize(child));
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([childKey, child]) => [childKey, sanitize(child, childKey)]),
    );
  }
  return value;
}

const client = new api.StorageAPIClient('127.0.0.1:16051', grpc.credentials.createInsecure());
const call = client.storageInfo(new messages.StorageInfoRequest());
const timer = setTimeout(() => {
  call.cancel();
  client.close();
  process.stderr.write('Drive storage stream timeout\n');
  process.exit(1);
}, 5000);

call.once('data', (message) => {
  clearTimeout(timer);
  process.stdout.write(`${JSON.stringify(sanitize(message.toObject()))}\n`);
  call.cancel();
  client.close();
  process.exit(0);
});
call.once('error', (error) => {
  if (error.code === grpc.status.CANCELLED) return;
  clearTimeout(timer);
  client.close();
  process.stderr.write(`Drive storage query failed: ${error.message}\n`);
  process.exit(1);
});
