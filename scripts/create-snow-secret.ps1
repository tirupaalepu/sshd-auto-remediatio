# Create/update Secrets Manager secret from local .env (run from repo root).
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root ".env"
if (-not (Test-Path $envFile)) {
  throw "Missing .env - copy .env.example to .env and fill SNOW_* values."
}

$vals = @{}
Get-Content $envFile | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
  $k, $v = $_ -split '=', 2
  $vals[$k.Trim()] = $v.Trim()
}

foreach ($req in @("SNOW_INSTANCE", "SNOW_USER", "SNOW_PASSWORD")) {
  if (-not $vals.ContainsKey($req) -or [string]::IsNullOrWhiteSpace($vals[$req])) {
    throw "Missing $req in .env"
  }
}

$secretName = "sshd-auto-remediation/servicenow"
$payload = '{"instance":"' + $vals["SNOW_INSTANCE"].TrimEnd("/").Replace('\','\\').Replace('"','\"') + '","user":"' + $vals["SNOW_USER"].Replace('\','\\').Replace('"','\"') + '","password":"' + $vals["SNOW_PASSWORD"].Replace('\','\\').Replace('"','\"') + '"}'
$tmp = Join-Path $env:TEMP ("snow-secret-" + [guid]::NewGuid().ToString() + ".json")
[System.IO.File]::WriteAllText($tmp, $payload)

try {
  aws secretsmanager put-secret-value --secret-id $secretName --secret-string ("file://" + $tmp.Replace('\','/')) 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    aws secretsmanager create-secret --name $secretName --secret-string ("file://" + $tmp.Replace('\','/')) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to create/update secret" }
    Write-Host "Created secret: $secretName"
  } else {
    Write-Host "Updated secret: $secretName"
  }
  Write-Host ("password_len=" + $vals["SNOW_PASSWORD"].Length)
} finally {
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
