# Avisador de Treinamentos Mavaular
# Lê a agenda publicada no portal e mostra uma notificação do Windows:
#   - na véspera (a partir das 8h), no dia do treinamento e 1 hora antes do início.
# Instalado pelo "instalar.bat"; roda escondido a cada 30 minutos e ao entrar no Windows.
param([switch]$Teste, [string]$Arquivo = "", [string]$Agora = "")

$ErrorActionPreference = "Stop"
$AgendaUrl = "https://treinamentos-mavaular.netlify.app/agenda.ics"
$PortalUrl = "https://treinamentos-mavaular.netlify.app"
# Guarda a cópia da agenda e os avisos já mostrados na pasta do próprio avisador (ou na pasta temporária)
$Pasta = $null
$candidatas = @($PSScriptRoot)
if ($env:LOCALAPPDATA) { $candidatas += (Join-Path $env:LOCALAPPDATA "TreinamentosMavaular") }
$candidatas += (Join-Path ([IO.Path]::GetTempPath()) "TreinamentosMavaular")
foreach ($cand in $candidatas) {
    if (-not $cand) { continue }
    try {
        New-Item -ItemType Directory -Force -Path $cand -ErrorAction Stop | Out-Null
        $t = Join-Path $cand ".teste-gravacao"; [IO.File]::WriteAllText($t, "ok"); Remove-Item $t -Force
        $Pasta = $cand; break
    } catch { }
}
if (-not $Pasta) { $Pasta = [IO.Path]::GetTempPath() }
$Cache     = Join-Path $Pasta "agenda.ics"
$Estado    = Join-Path $Pasta "avisos-mostrados.txt"

function Mostrar-Aviso([string]$Titulo, [string]$Linha1, [string]$Linha2, [string]$Link) {
    if ($env:AVISO_SIMULAR) { Write-Output ("AVISO | {0} | {1} | {2} | {3}" -f $Titulo, $Linha1, $Linha2, $Link); return }
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
    $e = [System.Security.SecurityElement]
    $xml = @"
<toast scenario="reminder" launch="$($e::Escape($Link))" activationType="protocol">
  <visual><binding template="ToastGeneric">
    <text>$($e::Escape($Titulo))</text>
    <text>$($e::Escape($Linha1))</text>
    <text>$($e::Escape($Linha2))</text>
  </binding></visual>
  <actions>
    <action content="Ver detalhes" activationType="protocol" arguments="$($e::Escape($Link))"/>
    <action content="Fechar" activationType="system" arguments="dismiss"/>
  </actions>
  <audio src="ms-winsoundevent:Notification.Reminder"/>
</toast>
"@
    $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
    $doc.LoadXml($xml)
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show((New-Object Windows.UI.Notifications.ToastNotification $doc))
}

if ($Teste) {
    Mostrar-Aviso "Treinamentos Mavaular" "O avisador está funcionando." "Você será avisado na véspera, no dia e 1 hora antes de cada treinamento." $PortalUrl
    exit 0
}

# 1. Baixar a agenda (se estiver sem internet, usa a última cópia)
$texto = $null
if ($Arquivo) { $texto = [IO.File]::ReadAllText($Arquivo, [Text.Encoding]::UTF8) }
else {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object Net.WebClient
        $wc.Encoding = [Text.Encoding]::UTF8
        $wc.Headers.Add("Cache-Control", "no-cache")
        $texto = $wc.DownloadString($AgendaUrl + "?t=" + [DateTime]::Now.Ticks)
        [IO.File]::WriteAllText($Cache, $texto, (New-Object Text.UTF8Encoding $false))
    } catch {
        if (Test-Path $Cache) { $texto = [IO.File]::ReadAllText($Cache, [Text.Encoding]::UTF8) } else { exit 0 }
    }
}

# 2. Ler os eventos do arquivo de agenda
$linhas = New-Object System.Collections.Generic.List[string]
foreach ($l in ($texto -split "`r?`n")) {
    if (($l.StartsWith(" ") -or $l.StartsWith("`t")) -and $linhas.Count -gt 0) { $linhas[$linhas.Count - 1] += $l.Substring(1) }
    elseif ($l -ne "") { $linhas.Add($l) }
}
function Limpar([string]$v) { return ($v -replace '\\n', ' · ' -replace '\\,', ',' -replace '\\;', ';' -replace '\\\\', '\') }

$eventos = @(); $ev = $null; $emAlarme = $false
foreach ($l in $linhas) {
    if ($l -eq "BEGIN:VEVENT") { $ev = @{ Hora = $true }; continue }
    if ($l -eq "END:VEVENT") { if ($ev -and $ev.Inicio) { $eventos += [pscustomobject]$ev }; $ev = $null; continue }
    if ($l -eq "BEGIN:VALARM") { $emAlarme = $true; continue }
    if ($l -eq "END:VALARM") { $emAlarme = $false; continue }
    if (-not $ev -or $emAlarme) { continue }
    $i = $l.IndexOf(":"); if ($i -lt 1) { continue }
    $chave = $l.Substring(0, $i); $valor = $l.Substring($i + 1); $nome = ($chave -split ";")[0]
    switch ($nome) {
        "UID"      { $ev.Uid = $valor }
        "SUMMARY"  { $ev.Titulo = (Limpar $valor) -replace '^Treinamento: ', '' }
        "LOCATION" { $ev.Local = Limpar $valor }
        "URL"      { $ev.Link = $valor }
        "DTSTART"  {
            if ($chave -match "VALUE=DATE") { $ev.Inicio = [DateTime]::ParseExact($valor, "yyyyMMdd", $null); $ev.Hora = $false }
            else { $ev.Inicio = [DateTime]::ParseExact($valor.TrimEnd("Z"), "yyyyMMdd'T'HHmmss", $null) }
        }
    }
}

# 3. Decidir o que avisar agora
$agoraDt = Get-Date
if ($Agora) { $agoraDt = [DateTime]::ParseExact($Agora, "yyyy-MM-dd HH:mm", $null) }
$hoje = $agoraDt.Date
$mostrados = @{}
if (Test-Path $Estado) { foreach ($k in (Get-Content $Estado -Encoding UTF8)) { $mostrados[$k] = $true } }
$novos = @()

foreach ($e in $eventos) {
    $dia = $e.Inicio.Date
    $quando = "Dia inteiro"
    if ($e.Hora) { $quando = "às " + $e.Inicio.ToString("HH:mm") }
    $local = ""; if ($e.Local) { $local = $e.Local }
    $link = $PortalUrl; if ($e.Link) { $link = $e.Link }
    $aviso = $null; $tipo = $null

    if ($e.Hora -and $agoraDt -ge $e.Inicio.AddHours(-1) -and $agoraDt -lt $e.Inicio) {
        $min = [int][Math]::Ceiling(($e.Inicio - $agoraDt).TotalMinutes)
        $tipo = "1h"; $aviso = @("Treinamento em $min minutos", "$($e.Titulo) — $quando", $local)
    }
    elseif ($dia -eq $hoje -and (-not $e.Hora -or $agoraDt -lt $e.Inicio.AddMinutes(30))) {
        $tipo = "dia"; $aviso = @("Hoje tem treinamento", "$($e.Titulo) — $quando", $local)
    }
    elseif ($dia -eq $hoje.AddDays(1) -and $agoraDt.Hour -ge 8) {
        $tipo = "vespera"; $aviso = @("Amanhã tem treinamento", "$($e.Titulo) — $quando", $local)
    }
    if (-not $aviso) { continue }
    $id = "{0}|{1}|{2}" -f $e.Uid, $e.Inicio.ToString("yyyyMMddHHmm"), $tipo
    if ($mostrados.ContainsKey($id)) { continue }
    # se o aviso de 1 hora já saiu, não repete o "hoje"
    if ($tipo -eq "dia" -and $mostrados.ContainsKey(("{0}|{1}|1h" -f $e.Uid, $e.Inicio.ToString("yyyyMMddHHmm")))) { continue }
    try { Mostrar-Aviso $aviso[0] $aviso[1] $aviso[2] $link; $novos += $id } catch { }
}

if ($novos.Count -gt 0) { Add-Content -Path $Estado -Value $novos -Encoding UTF8 }
