# Solicita IPs de início e fim
$startIP = Read-Host "Informe o IP inicial (ex: 192.168.1.10)"
$endIP = Read-Host "Informe o IP final (ex: 192.168.1.20)"

# Converte IP para número
function ConvertTo-DecimalIP ($ip) {
    $parts = $ip.Split('.')
    return ($parts[0] -as [int]) * 16777216 + ($parts[1] -as [int]) * 65536 + ($parts[2] -as [int]) * 256 + ($parts[3] -as [int])
}

function ConvertFrom-DecimalIP ($decimal) {
    $a = [math]::Floor($decimal / 16777216)
    $b = [math]::Floor(($decimal % 16777216) / 65536)
    $c = [math]::Floor(($decimal % 65536) / 256)
    $d = $decimal % 256
    return "$a.$b.$c.$d"
}

$startDecimal = ConvertTo-DecimalIP $startIP
$endDecimal = ConvertTo-DecimalIP $endIP

# Limite de jobs simultâneos
$maxJobs = 50
$jobs = @()

# Caminho do CSV
$csvPath = Join-Path -Path $PSScriptRoot -ChildPath "resultado-ping.csv"
$results = @()

# Função para resolver hostname (dentro do job)
function Get-Hostname {
    param ($ip)
    try {
        $entry = [System.Net.Dns]::GetHostEntry($ip)
        return $entry.HostName
    } catch {
        return "N/A"
    }
}

# Inicia os jobs
function Start-PingJob {
    param ($ip)

    Start-Job -ScriptBlock {
        param ($ip)

        $status = if (ping -n 1 -w 100 $ip | Select-String "TTL=") {
            "Ativo"
        } else {
            "Inativo"
        }

        $hostname = try {
            [System.Net.Dns]::GetHostEntry($ip).HostName
        } catch {
            "N/A"
        }

        [PSCustomObject]@{
            IP       = $ip
            Hostname = $hostname
            Status   = $status
            DataHora = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    } -ArgumentList $ip
}

# Loop para criar os jobs
for ($i = $startDecimal; $i -le $endDecimal; $i++) {
    $ip = ConvertFrom-DecimalIP $i

    while (@(Get-Job -State Running).Count -ge $maxJobs) {
        Start-Sleep -Milliseconds 100
    }

    $jobs += Start-PingJob -ip $ip
}

# Espera todos os jobs finalizarem
Write-Host "`nAguardando finalização dos testes..." -ForegroundColor Yellow
$jobs | ForEach-Object { $_ | Wait-Job }

# Recebe e salva os resultados
$results = $jobs | ForEach-Object {
    $res = Receive-Job -Job $_
    Remove-Job -Job $_
    $res
}

Write-Host "`nSalvando resultados em: $csvPath" -ForegroundColor Cyan
$results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "`nConcluído!" -ForegroundColor Green