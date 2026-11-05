$ErrorActionPreference = 'Stop'
# Paste the token locally, never into chat or the project. No shell history entry.
$configDir = Join-Path $env:USERPROFILE '.cpolar'
$config = Join-Path $configDir 'cpolar.yml'
Write-Host 'Log in at https://dashboard.cpolar.com and open Auth / authentication.'
$secret = Read-Host 'Paste your cpolar authtoken (hidden)' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
try {
    $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer).Trim()
    if ($token -notmatch '^[a-zA-Z0-9_-]{16,256}$') { throw 'Invalid token format.' }
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    $content = if (Test-Path -LiteralPath $config) { [IO.File]::ReadAllText($config) } else { '' }
    if ($content -match '(?m)^authtoken:') { $content = [regex]::Replace($content,'(?m)^authtoken:.*$',('authtoken: '+$token)) }
    else { $content = "authtoken: $token`n" + $content }
    [IO.File]::WriteAllText($config,$content,[Text.UTF8Encoding]::new($false))
    Write-Host 'Account configured locally. Run start_public_test.bat.'
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    $token=$null; $content=$null; $secret.Dispose()
}
