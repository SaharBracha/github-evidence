#!/usr/bin/env node
// (c) JFrog Ltd. (2026)
// Build a DSSE envelope by signing a prepare-API payload with a local PEM key.
// Matches the Evidence platform's expected PAE + RSA-SHA256 (PKCS#1) scheme;
// also supports ECDSA-SHA256 and Ed25519.
//
// Usage:
//   sign-dsse.mjs --payload-b64 <b64> --payload-type <type> --key <pem> --key-id <alias>
//   sign-dsse.mjs --prepare-response <file> --key <pem> --key-id <alias>
// Prints the DSSE envelope JSON on stdout.

import { createPrivateKey, createSign, constants, sign as cryptoSign } from 'node:crypto';
import { readFileSync } from 'node:fs';

function usage() {
  process.stderr.write(
    'Usage: sign-dsse.mjs (--prepare-response <file> | --payload-b64 <b64> --payload-type <type>) ' +
      '--key <pem-path> --key-id <alias>\n',
  );
  process.exit(2);
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) usage();
    const key = a.slice(2);
    const val = argv[++i];
    if (val === undefined) usage();
    out[key] = val;
  }
  return out;
}

function buildPaeBuffer(payloadType, payload) {
  const head = `DSSEv1 ${payloadType.length} ${payloadType} ${payload.length} `;
  return Buffer.concat([Buffer.from(head, 'utf8'), payload]);
}

function signPae(key, paeBuf) {
  const type = key.asymmetricKeyType;
  if (type === 'rsa' || type === 'rsa-pss') {
    const signer = createSign('RSA-SHA256');
    signer.update(paeBuf);
    signer.end();
    return signer.sign({ key, padding: constants.RSA_PKCS1_PADDING });
  }
  if (type === 'ec') {
    const signer = createSign('SHA256');
    signer.update(paeBuf);
    signer.end();
    return signer.sign(key);
  }
  if (type === 'ed25519') {
    return cryptoSign(null, paeBuf, key);
  }
  throw new Error(`unsupported private key type: ${type}`);
}

function signIntotoEnvelope(payloadBase64, payloadType, keyPem, keyId) {
  const key = createPrivateKey(keyPem);
  const payload = Buffer.from(payloadBase64, 'base64');
  const paeBuf = buildPaeBuffer(payloadType, payload);
  const sigB64 = signPae(key, paeBuf).toString('base64');
  return {
    payload: payloadBase64,
    payloadType,
    signatures: [{ keyid: keyId, sig: sigB64 }],
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.key || !args['key-id']) usage();

  let payloadB64 = args['payload-b64'];
  let payloadType = args['payload-type'];

  if (args['prepare-response']) {
    const prep = JSON.parse(readFileSync(args['prepare-response'], 'utf8'));
    payloadB64 = prep.dsse_payload;
    payloadType = prep.dsse_payload_type;
  }

  if (!payloadB64 || !payloadType) {
    process.stderr.write('missing dsse_payload / dsse_payload_type\n');
    process.exit(1);
  }

  const keyPem = readFileSync(args.key, 'utf8');
  const envelope = signIntotoEnvelope(payloadB64, payloadType, keyPem, args['key-id']);
  process.stdout.write(JSON.stringify(envelope));
}

main();
