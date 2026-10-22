$ErrorActionPreference = 'Stop'
$project155 = Split-Path $PSScriptRoot -Parent
Set-Location $project155
if ([IO.File]::ReadAllText((Join-Path $project155 'supabase\config.toml')) -notmatch '(?m)^project_id\s*=\s*"unimis"\s*$') { throw 'This setup is for the local unimis project only.' }
$container155 = 'supabase_db_unimis'
$running155 = @(& docker ps --filter 'name=^/supabase_db_unimis$' --format '{{.Names}}')
if ($LASTEXITCODE -ne 0 -or $running155 -notcontains $container155) { throw 'Start the local UniMIS Supabase project first.' }
function RunSql155([string]$name155) {
 Get-Content -LiteralPath (Join-Path $PSScriptRoot $name155) -Raw | & docker exec -i $container155 psql -X -U postgres -d postgres -v ON_ERROR_STOP=1
 if ($LASTEXITCODE -ne 0) { throw ($name155 + ' failed. No triggers or security checks were disabled.') }
}
RunSql155 'Preflight_Local_Accounts.sql'
$statusText155 = (& $env:ComSpec /d /c 'npx.cmd supabase status -o json 2>nul' | Out-String)
if ($LASTEXITCODE -ne 0 -or $statusText155.IndexOf('{') -lt 0) { throw 'Could not read local Supabase status.' }
$status155 = $statusText155.Substring($statusText155.IndexOf('{')) | ConvertFrom-Json
$api155 = $status155.API_URL
$service155 = $status155.SERVICE_ROLE_KEY
$public155 = $status155.PUBLISHABLE_KEY
if (!$public155) { $public155 = $status155.ANON_KEY }
if (!$api155 -or !$service155 -or !$public155) { throw 'Local Supabase API URL and keys were not found. Do not paste keys into chat.' }
$uri155 = [Uri]$api155
if ($uri155.Host -notin @('127.0.0.1','localhost') -or $uri155.Scheme -ne 'http') { throw 'Only local HTTP Supabase is supported.' }
$headers155 = @{apikey=$service155; Authorization=('Bearer ' + $service155)}
function Plain155($secure155) { $ptr155=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure155); try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr155) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr155) } }
foreach ($email155 in @('kk@gmail.com','pp@gmail.com')) {
 $query155 = "SELECT count(*) FROM auth.users WHERE lower(email)='$email155';"
 $exists155 = ($query155 | & docker exec -i $container155 psql -X -U postgres -d postgres -tA -v ON_ERROR_STOP=1 | Out-String).Trim()
 if ($LASTEXITCODE -ne 0 -or $exists155 -notmatch '^[01]$') { throw 'Account lookup failed.' }
 if ($exists155 -eq '1') { Write-Host ('Existing account retained; password unchanged: ' + $email155); continue }
 $one155 = Read-Host ('Choose a password for ' + $email155 + ' (at least 8 characters)') -AsSecureString
 $two155 = Read-Host 'Confirm password' -AsSecureString
 $password155=Plain155 $one155; $confirm155=Plain155 $two155
 try {
  if ($password155.Length -lt 8 -or $password155 -cne $confirm155) { throw 'Passwords must match and have at least 8 characters. Rerun setup.' }
  $body155 = @{email=$email155;password=$password155;email_confirm=$true;user_metadata=@{account_type='staff'}} | ConvertTo-Json -Depth 4
  try { $created155 = Invoke-RestMethod -Uri ($api155.TrimEnd('/') + '/auth/v1/admin/users') -Method Post -Headers $headers155 -ContentType 'application/json' -Body $body155 }
  catch { throw ('Auth account creation failed for ' + $email155 + '. Check local Auth service health/password policy. No password or key is printed.') }
  if (!$created155.id) { throw 'Auth did not return a user ID.' }
  Write-Host ('Created confirmed local account: ' + $email155)
 } finally { $password155=$null; $confirm155=$null; $body155=$null; $one155.Dispose(); $two155.Dispose() }
}
RunSql155 'Grant_Local_Accounts.sql'
# Point the existing React app at this local stack; no service key enters the frontend.
$env155=Join-Path $project155 '.env'
$lines155=@()
if (Test-Path -LiteralPath $env155) {
 Copy-Item -LiteralPath $env155 -Destination ($env155 + '.before155-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.bak')
 $lines155=@(Get-Content -LiteralPath $env155 | Where-Object { $_ -notmatch '^\s*VITE_SUPABASE_(URL|PUBLISHABLE_KEY)\s*=' })
}
$lines155 += ('VITE_SUPABASE_URL=' + $api155)
$lines155 += ('VITE_SUPABASE_PUBLISHABLE_KEY=' + $public155)
[IO.File]::WriteAllLines($env155,[string[]]$lines155,(New-Object System.Text.UTF8Encoding($false)))
$headers155.Clear();$service155=$null;$public155=$null;$status155=$null;$statusText155=$null
Write-Host 'SUCCESS. Owner: kk@gmail.com. Registrar: pp@gmail.com.'
Write-Host 'Sign in using the passwords entered privately. Restart npm run dev after the local .env update.'
Write-Host 'No student accounts, demo data, additional roles or platform operator access were created.'
