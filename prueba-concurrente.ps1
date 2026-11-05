param(
    [string]$Collection = "fibonacci.postman_collection.json",
    [int]$Concurrent = 10,
    [string]$OutDir = "resultados"
)

# --- Validaciones ---
if (-not (Get-Command newman -ErrorAction SilentlyContinue)) {
    Write-Error "No se encontro newman. Instalalo con: npm install -g newman"
    exit 1
}
if (-not (Test-Path $Collection)) {
    Write-Error "No se encontro la coleccion '$Collection'. Ejecuta el script desde la carpeta donde esta."
    exit 1
}

$collectionPath = (Resolve-Path $Collection).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$outPath = (Resolve-Path $OutDir).Path

# --- Lanzar las peticiones en paralelo ---
Write-Host "Lanzando $Concurrent peticiones concurrentes..." -ForegroundColor Cyan
$inicio = Get-Date

$jobs = 1..$Concurrent | ForEach-Object {
    Start-Job -ScriptBlock {
        param($i, $col, $out)
        $archivo = Join-Path $out "result_$i.json"
        newman run $col --reporters json --reporter-json-export $archivo | Out-Null
    } -ArgumentList $_, $collectionPath, $outPath
}

$jobs | Wait-Job | Out-Null
$total = ((Get-Date) - $inicio).TotalSeconds
$jobs | Remove-Job -Force

# --- Leer resultados ---
$filas = 1..$Concurrent | ForEach-Object {
    $archivo = Join-Path $outPath "result_$_.json"
    $http = "sin resultado"
    $tiempo = $null
    $ok = $false

    if (Test-Path $archivo) {
        $r = Get-Content $archivo -Raw | ConvertFrom-Json
        $e = $r.run.executions[0]
        if ($e.response) {
            $http = $e.response.code
            $tiempo = $e.response.responseTime
            $ok = ($http -eq 200)
        } else {
            $http = "sin respuesta"
        }
    }

    [pscustomobject]@{
        Peticion = $_
        HTTP     = $http
        TiempoMs = $tiempo
        OK       = $ok
    }
}

# --- Resumen ---
Write-Host ""
$filas | Format-Table -AutoSize

$tiempos = $filas | Where-Object { $null -ne $_.TiempoMs } | ForEach-Object { $_.TiempoMs }
$exitosas = ($filas | Where-Object { $_.OK }).Count

Write-Host "Peticiones exitosas (200 OK): $exitosas de $Concurrent"
if ($tiempos) {
    $stats = $tiempos | Measure-Object -Average -Minimum -Maximum
    Write-Host ("Tiempo promedio: {0:N0} ms" -f $stats.Average)
    Write-Host ("Tiempo minimo:   {0:N0} ms" -f $stats.Minimum)
    Write-Host ("Tiempo maximo:   {0:N0} ms" -f $stats.Maximum)
}
Write-Host ("Duracion total de la prueba: {0:N1} s" -f $total)

# --- Guardar CSV para el informe ---
$csv = Join-Path $outPath "resumen.csv"
$filas | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Host "Resumen guardado en $csv" -ForegroundColor Green