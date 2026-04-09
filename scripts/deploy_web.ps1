<#
scripts/deploy_web.ps1

Uso:
  .\scripts\deploy_web.ps1 -FirebaseProject "my-firebase-project"

Requisitos:
  - Flutter en PATH
  - firebase-tools instalados (`npm i -g firebase-tools`)
  - Autenticación: `firebase login` (o usar la variable de entorno FIREBASE_TOKEN)

Este script construye la versión web release y la despliega a Firebase Hosting.
#>

param(
  [string]$FirebaseProject = '',
  [switch]$SkipBuild
)

Write-Host "Starting Flutter web deploy..."

if (-not $SkipBuild) {
  Write-Host "Running: flutter pub get"
  & flutter pub get
  if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed ($LASTEXITCODE)" }

  Write-Host "Running: flutter build web --release"
  & flutter build web --release
  if ($LASTEXITCODE -ne 0) { throw "flutter build web failed ($LASTEXITCODE)" }
} else {
  Write-Host "Skipping build (SkipBuild)."
}

$projectArg = ''
if ($FirebaseProject -ne '') { $projectArg = "--project $FirebaseProject" }

Write-Host "Deploying to Firebase Hosting..."
if ($env:FIREBASE_TOKEN) {
  & firebase deploy --only hosting $projectArg --token $env:FIREBASE_TOKEN
} else {
  & firebase deploy --only hosting $projectArg
}

Write-Host "Deploy finished."
