# Genera las imágenes de la interfaz del README (docs/images/ui-*.png):
#   1. Ejecuta el addon real sobre el cliente simulado en Docker y exporta el diseño (tools/ui-preview/scenes.js).
#   2. Abre tools/ui-preview/preview.html con Microsoft Edge sin ventana y guarda una captura por escena.
# Uso (desde cualquier carpeta): powershell -File tools/ui-preview/render.ps1
# Requisitos: Docker con la imagen richarsilus-dev (docker build -t richarsilus-dev tools) y Microsoft Edge.
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$previewDirectory = Join-Path $repositoryRoot 'tools\ui-preview'
$imagesDirectory = Join-Path $repositoryRoot 'docs\images'
$scenes = @('main', 'confirm')

# Ventana de 640x640 más 16 px de margen por lado; escala 2 para que el texto se lea bien en GitHub.
$windowSize = '672,672'
$deviceScaleFactor = '2'

docker run --rm -v "${repositoryRoot}:/addon" richarsilus-dev lua5.1 tools/ui-preview/export.lua
if ($LASTEXITCODE -ne 0) {
  throw "Exporting the layout failed (docker exit code $LASTEXITCODE)."
}

$edgeCandidates = @(
  (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
  (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
)
$edge = $edgeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) {
  throw 'Microsoft Edge was not found.'
}

New-Item -ItemType Directory -Force $imagesDirectory | Out-Null
$profileDirectory = Join-Path ([IO.Path]::GetTempPath()) ('richarsilus-edge-' + [Guid]::NewGuid())
try {
  foreach ($scene in $scenes) {
    $pageUri = ([Uri](Join-Path $previewDirectory 'preview.html')).AbsoluteUri + "?scene=$scene"
    $imagePath = Join-Path $imagesDirectory "ui-$scene.png"
    if (Test-Path $imagePath) {
      Remove-Item $imagePath
    }
    $arguments = @(
      '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
      "--user-data-dir=`"$profileDirectory`"",
      "--force-device-scale-factor=$deviceScaleFactor",
      "--window-size=$windowSize",
      '--virtual-time-budget=2000',
      "--screenshot=`"$imagePath`"",
      "`"$pageUri`""
    )
    Start-Process -FilePath $edge -ArgumentList $arguments -Wait -NoNewWindow
    if (-not (Test-Path $imagePath)) {
      throw "Edge did not write $imagePath."
    }
    Write-Output $imagePath
  }
}
finally {
  if (Test-Path $profileDirectory) {
    Remove-Item -Recurse -Force $profileDirectory
  }
}
