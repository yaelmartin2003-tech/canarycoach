// cleanup_firestore.js
// Limpia Firestore: borra usuarios de prueba, chats, user_rich_data y app_state/users.
// Mantiene el admin y lista los access_keys para revisión manual.
//
// Uso: node cleanup_firestore.js

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: serviceAccount.project_id,
});

const db = admin.firestore();
db.settings({ ignoreUndefinedProperties: true });

const ADMIN_EMAIL = 'yaelmartin2003@gmail.com';

// access_keys que se conservan
const KEEP_ACCESS_KEYS = new Set(['ENTR-K5SBWR', 'TRUP-622XC4NN', 'ADMIN123']);

async function getAdminUid() {
  const snap = await db
    .collection('users')
    .where('email', '==', ADMIN_EMAIL)
    .limit(1)
    .get();
  if (snap.empty) {
    throw new Error(`No se encontró ningún doc en users/ con email=${ADMIN_EMAIL}`);
  }
  return snap.docs[0].id;
}

async function deleteCollectionExcept(colName, exceptUid) {
  const snap = await db.collection(colName).get();
  let deleted = 0;
  for (const doc of snap.docs) {
    if (doc.id !== exceptUid) {
      await doc.ref.delete();
      deleted++;
      console.log(`  Borrado ${colName}/${doc.id}`);
    }
  }
  console.log(`  → ${deleted} docs borrados de ${colName}/ (conservado: ${exceptUid})`);
}

async function deleteCollectionFull(colName) {
  const snap = await db.collection(colName).get();
  let deleted = 0;
  for (const doc of snap.docs) {
    // Borrar subcolección messages si existe (chats)
    const msgsSnap = await doc.ref.collection('messages').get();
    for (const msg of msgsSnap.docs) {
      await msg.ref.delete();
    }
    await doc.ref.delete();
    deleted++;
    console.log(`  Borrado ${colName}/${doc.id} (+ ${msgsSnap.size} mensajes)`);
  }
  console.log(`  → ${deleted} docs borrados de ${colName}/`);
}

async function deleteDocument(docPath) {
  await db.doc(docPath).delete();
  console.log(`  Borrado doc: ${docPath}`);
}

async function cleanAccessKeys() {
  const snap = await db.collection('access_keys').get();
  let deleted = 0;
  let kept = 0;
  for (const doc of snap.docs) {
    if (KEEP_ACCESS_KEYS.has(doc.id)) {
      console.log(`  Conservado access_keys/${doc.id}  →  ${JSON.stringify(doc.data())}`);
      kept++;
    } else {
      await doc.ref.delete();
      console.log(`  Borrado  access_keys/${doc.id}`);
      deleted++;
    }
  }
  console.log(`  → ${deleted} borrados, ${kept} conservados`);
}

async function main() {
  console.log('Buscando UID del admin...');
  const adminUid = await getAdminUid();
  console.log(`Admin UID: ${adminUid}\n`);

  console.log('1. Borrando users/ (excepto admin)...');
  await deleteCollectionExcept('users', adminUid);

  console.log('\n2. Borrando user_rich_data/ (excepto admin)...');
  await deleteCollectionExcept('user_rich_data', adminUid);

  console.log('\n3. Borrando chats/ (todos)...');
  await deleteCollectionFull('chats');

  console.log('\n4. Borrando app_state/users...');
  try {
    await deleteDocument('app_state/users');
  } catch (e) {
    console.log('  (app_state/users no existía o ya estaba vacío)');
  }

  console.log('\n5. Limpiando access_keys (conservando 3)...');
  await cleanAccessKeys();

  console.log('\n✅ Limpieza completada.');
  process.exit(0);
}

main().catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
