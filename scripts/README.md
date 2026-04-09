Deploy scripts
=================

Archivos añadidos:

- `scripts/deploy_web.ps1` - PowerShell helper para build + firebase deploy (Windows/PowerShell).
- `scripts/deploy_web.sh`  - Bash helper para build + firebase deploy (Linux/macOS/CI).
- `.github/workflows/deploy-web.yml` - ejemplo de workflow para GitHub Actions.

Uso rápido (local):

PowerShell:
```powershell
# con proyecto explícito:
.\scripts\deploy_web.ps1 -FirebaseProject "mi-proyecto"

# si ya logueado con firebase CLI:
.\scripts\deploy_web.ps1
```

Bash:
```bash
# con proyecto explícito
./scripts/deploy_web.sh mi-proyecto-id

# o solo
./scripts/deploy_web.sh
```

CI (GitHub Actions):
- Crea secrets `FIREBASE_SERVICE_ACCOUNT` (JSON de cuenta de servicio, base64 o raw según la acción) y `FIREBASE_PROJECT_ID`.
- El workflow `deploy-web.yml` en `.github/workflows` construirá y desplegará al hacer push en `main`.

Notas:
- Asegúrate de tener `firebase-tools` instalado y configurado.
- Para despliegues desde CI es práctica común usar una cuenta de servicio y la acción `FirebaseExtended/action-hosting-deploy@v0`.
