param(
    [Parameter(Mandatory = $true)]
    [string]$Fqdn,

    [Parameter(Mandatory = $true)]
    [int]$Port,

    [int]$MaxAttempts = 60,
    [int]$DelaySeconds = 10,
    [int]$TimeoutMilliseconds = 5000,
    [int]$PostResolveDelaySeconds = 0
)

$ErrorActionPreference = 'Stop'

function Test-PrivateIp {
    param([string]$Ip)

    if ([string]::IsNullOrWhiteSpace($Ip)) {
        return $false
    }

    return $Ip.StartsWith('10.') -or
           $Ip.StartsWith('192.168.') -or
           $Ip -match '^172\.(1[6-9]|2[0-9]|3[0-1])\.'
}

function Get-ResolvedAddresses {
    param([string]$HostName)

    try {
        return [System.Net.Dns]::GetHostAddresses($HostName) |
            Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
            ForEach-Object { $_.IPAddressToString }
    }
    catch {
        return @()
    }
}

function Test-TcpPort {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutMilliseconds = 5000
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $asyncResult = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) {
            return $false
        }

        $client.EndConnect($asyncResult)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

Write-Host "Waiting for private DNS and connectivity for ${Fqdn}:${Port}"

for ($i = 1; $i -le $MaxAttempts; $i++) {
    $ips = @(Get-ResolvedAddresses -HostName $Fqdn)
    if ($ips.Count -gt 0) {
        Write-Host "Resolved $Fqdn to: $($ips -join ', ')"
        $privateIps = @($ips | Where-Object { Test-PrivateIp $_ })
        if ($privateIps.Count -gt 0) {
            $tcpOk = Test-TcpPort -HostName $Fqdn -Port $Port -TimeoutMilliseconds $TimeoutMilliseconds
            if ($tcpOk) {
                if ($PostResolveDelaySeconds -gt 0) {
                    Write-Host "Private connectivity confirmed. Waiting ${PostResolveDelaySeconds}s for private link propagation..."
                    Start-Sleep -Seconds $PostResolveDelaySeconds
                }
                Write-Host "Private connectivity is ready for $Fqdn"
                exit 0
            }

            Write-Host "Private DNS is ready, but TCP $Port is not reachable yet."
        }
    }
    else {
        Write-Host "DNS lookup returned no IPv4 addresses for $Fqdn"
    }

    if ($i -lt $MaxAttempts) {
        Start-Sleep -Seconds $DelaySeconds
    }
}

throw "Timed out waiting for private DNS/connectivity for $Fqdn"