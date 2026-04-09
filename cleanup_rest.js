// cleanup_rest.js
// Usa Firestore REST API con JWT manual (compensa desfase de reloj de Windows).

const https = require('https');
const crypto = require('crypto');
const key = require('./serviceAccountKey.json');

const ADMIN_EMAIL = 'yaelmartin2003@gmail.com';
const KEEP_ACCESS_KEYS = new Set(['ENTR-K5SBWR', 'TRUP-622XC4NN', 'ADMIN123']);
const PROJECT = key.project_id;
const BASE = `projects/${PROJECT}/databases/(default)/documents`;

// ── JWT con corrección de reloj ──────────────────────────────────
function makeJwt() {
  // Restamos 65 seg para compensar el reloj adelantado (margen seguro)
  const now = Math.floor(Date.now() / 1000) - 3660;
  const header = Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({
    iss: key.client_email,
    sub: key.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/datastore',
  })).toString('base64url');
  const sig = crypto.sign('RSA-SHA256', Buffer.from(`${header}.${payload}`), key.private_key);
  return `${header}.${payload}.${sig.toString('base64url')}`;
}

function getAccessToken() {
  return new Promise((resolve, reject) => {
    const jwtToken = makeJwt();
    const body = `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwtToken}`;
    const options = {
      hostname: 'oauth2.googleapis.com',
      path: '/token',
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': body.length },
    };
    const req = https.request(options, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        const j = JSON.parse(data);
        if (j.access_token) resolve(j.access_token);
        else reject(new Error('Token error: ' + data));
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function firestoreRequest(token, method, path, body) {
  return new Promise((resolve, reject) => {
    const bodyStr = body ? JSON.stringify(body) : null;
    const options = {
      hostname: 'firestore.googleapis.com',
      path: `/v1/${path}`,
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        ...(bodyStr ? { 'Content-Length': Buffer.byteLength(bodyStr) } : {}),
      },
    };
    const req = https.request(options, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try { resolve(res.statusCode < 300 ? (data ? JSON.parse(data) : {}) : JSON.parse(data)); }
        catch { resolve({ _raw: data, _status: res.statusCode }); }
      });
    });
    req.on('error', reject);
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

async function listDocs(token, collection) {
  const docs = [];
  let url = `${BASE}/${collection}?pageSize=100`;
  while (url) {
    const res = await firestoreRequest(token, 'GET', url);
    if (res.error) throw new Error(JSON.stringify(res.error));
    (res.documents || []).forEach(d => docs.push(d));
    url = res.nextPageToken ? `${BASE}/${collection}?pageSize=100&pageToken=${res.nextPageToken}` : null;
  }
  return docs;
}

async function listSubDocs(token, docPath) {
  const docs = [];
  const path = `${docPath}/messages?pageSize=100`;
  const res = await firestoreRequest(token, 'GET', path);
  (res.documents || []).forEach(d => docs.push(d));
  return docs;
}

async function deleteDoc(token, name) {
  await firestoreRequest(token, 'DELETE', name.replace('projects/', 'projects/'));
}

async function main() {
  console.log('Obteniendo token...');
  const token = await getAccessToken();
  console.log('Token OK\n');

  // 1. users/ — conservar solo admin
  console.log('1. Leyendo users/...');
  const users = await listDocs(token, 'users');
  let adminUid = null;
  for (const doc of users) {
    const uid = doc.name.split('/').pop();
    const email = doc.fields?.email?.stringValue;
    if (email?.toLowerCase() === ADMIN_EMAIL.toLowerCase()) {
      adminUid = uid;
      console.log(`  Conservado users/${uid} (admin)`);
    } else {
      await deleteDoc(token, doc.name);
      console.log(`  Borrado  users/${uid} | ${email}`);
    }
  }
  if (!adminUid) console.log('  ⚠ No se encontró el doc del admin en users/');
  console.log();

  // 2. user_rich_data/ — conservar solo admin
  console.log('2. Leyendo user_rich_data/...');
  const rich = await listDocs(token, 'user_rich_data');
  for (const doc of rich) {
    const uid = doc.name.split('/').pop();
    if (uid === adminUid) {
      console.log(`  Conservado user_rich_data/${uid} (admin)`);
    } else {
      await deleteDoc(token, doc.name);
      console.log(`  Borrado  user_rich_data/${uid}`);
    }
  }
  console.log();

  // 3. chats/ — borrar todos con sus mensajes
  console.log('3. Leyendo chats/...');
  const chats = await listDocs(token, 'chats');
  for (const doc of chats) {
    const id = doc.name.split('/').pop();
    const msgs = await listSubDocs(token, doc.name);
    for (const msg of msgs) await deleteDoc(token, msg.name);
    await deleteDoc(token, doc.name);
    console.log(`  Borrado  chats/${id} (+ ${msgs.length} mensajes)`);
  }
  console.log();

  // 4. app_state/users
  console.log('4. Borrando app_state/users...');
  try {
    await firestoreRequest(token, 'DELETE', `${BASE}/app_state/users`);
    console.log('  Borrado app_state/users');
  } catch { console.log('  (no existía)'); }
  console.log();

  // 5. access_keys — conservar solo los 3
  console.log('5. Leyendo access_keys/...');
  const keys = await listDocs(token, 'access_keys');
  for (const doc of keys) {
    const id = doc.name.split('/').pop();
    if (KEEP_ACCESS_KEYS.has(id)) {
      console.log(`  Conservado access_keys/${id}`);
    } else {
      await deleteDoc(token, doc.name);
      console.log(`  Borrado  access_keys/${id}`);
    }
  }

  console.log('\n✅ Limpieza completada.');
  process.exit(0);
}

main().catch(e => { console.error('Error:', e.message); process.exit(1); });
