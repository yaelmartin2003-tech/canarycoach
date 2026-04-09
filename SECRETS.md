# Gestión de credenciales (importante)

No almacenes claves privadas ni archivos JSON de cuentas de servicio en el repositorio.

Qué hice aquí:
- Eliminé `serviceAccountKey.json.json` del historial y del working tree.
- Añadí patrones a `.gitignore` para evitar reintroducir claves.

Cómo añadir una credencial de desarrollo (forma segura):

1. Genera la clave en la consola de Google Cloud (IAM → Service Accounts → Keys → Create key (JSON)).
2. Guarda el JSON en una carpeta segura fuera del repo, por ejemplo `C:\secrets\new-key.json`.
3. No subas el JSON al repositorio. Si necesitas que CI tenga la clave, usa Secret Manager o GitHub Secrets.

USO LOCAL (temporal):

PowerShell (solo para prueba rápida):
```
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\secrets\new-key.json"
```

O persistente en Windows:
```
setx GOOGLE_APPLICATION_CREDENTIALS "C:\secrets\new-key.json"
```

GitHub Actions (recomendado): crea un secret `GCP_SERVICE_ACCOUNT_JSON` y en el workflow usa `google-github-actions/auth@v1` con `credentials_json: ${{ secrets.GCP_SERVICE_ACCOUNT_JSON }}`.

Si no entiendes algún paso, dime y te lo hago paso a paso en la consola web.

---
AVISO: Si ya había una clave comprometida, revócala inmediatamente en Google Cloud (IAM → Service Accounts → Keys → Delete) antes de crear una nueva.
