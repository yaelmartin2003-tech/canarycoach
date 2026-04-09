// delete_weight_logs.js
// Elimina ejercicios con nombre en minúscula de exerciseWeightLogs en app_state/users.
// Uso: node delete_weight_logs.js

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: serviceAccount.project_id,
});

const db = admin.firestore();

// Nombres exactos a eliminar (tal como aparecen en Firestore)
const NAMES_TO_DELETE = new Set(['sentadilla zumo', 'press banca']);

async function run() {
  const ref = db.collection('app_state').doc('users');
  const snap = await ref.get();

  if (!snap.exists) {
    console.log('No existe app_state/users');
    process.exit(0);
  }

  const data = snap.data();
  const items = data.items;

  if (!Array.isArray(items)) {
    console.log('El campo items no es un array');
    process.exit(1);
  }

  let totalRemoved = 0;

  const updatedItems = items.map((user) => {
    if (!Array.isArray(user.exerciseWeightLogs)) return user;

    const before = user.exerciseWeightLogs.length;
    const filtered = user.exerciseWeightLogs.filter(
      (log) => !NAMES_TO_DELETE.has(log.exerciseName)
    );
    const removed = before - filtered.length;

    if (removed > 0) {
      console.log(`  Usuario ${user.id ?? user.email ?? '?'}: eliminadas ${removed} entradas`);
      totalRemoved += removed;
    }

    return { ...user, exerciseWeightLogs: filtered };
  });

  if (totalRemoved === 0) {
    console.log('No se encontraron entradas con esos nombres. Nada que hacer.');
    process.exit(0);
  }

  await ref.set({ ...data, items: updatedItems });
  console.log(`\nListo. ${totalRemoved} entrada(s) eliminada(s) y guardadas en Firestore.`);
  process.exit(0);
}

run().catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
