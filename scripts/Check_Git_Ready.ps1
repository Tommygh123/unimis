$ErrorActionPreference='Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if(!(Get-Command git -ErrorAction SilentlyContinue)){throw 'Git is not installed/on PATH. No repository changes made.'}
if(!(Test-Path -LiteralPath '.git')){throw 'No Git repository yet. Initialize your private repository, then run this check before adding/committing files.'}
$tracked=@(& git ls-files)
if($LASTEXITCODE -ne 0){throw 'Could not inspect tracked files.'}
$bad=@($tracked | Where-Object {($_ -match '(^|/)\.env($|\.)' -and $_ -notmatch '(^|/)\.env\.example$') -or $_ -match '\.(dump|backup|pem|key|zip|bak)(\.|$)' -or $_ -match '(^|/)(node_modules|dist|backups|\.temp|\.branches)/'})
if($bad.Count){$bad | ForEach-Object {Write-Host ('REMOVE FROM GIT TRACKING (keep local file): '+$_)};throw 'Private/generated files are already tracked. .gitignore alone cannot remove them.'}
# Check index candidates as well as tracked files, without printing key values.
$candidates=@(& git ls-files --cached --others --exclude-standard)
$findings=New-Object 'System.Collections.Generic.List[string]'
foreach($file in $candidates){
 if($file -notmatch '\.(js|jsx|ts|tsx|json|toml|sql|md|txt|yml|yaml|ps1)$' -or !(Test-Path -LiteralPath $file)){continue}
 if((Get-Item -LiteralPath $file -Force).Length -gt 5000000){continue}
 $text=[IO.File]::ReadAllText((Join-Path (Get-Location) $file))
 if($text -match '(?i)(sk_live_[A-Za-z0-9]{12,}|sb_secret_[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)'){$findings.Add($file)}
}
if($findings.Count){$findings | ForEach-Object {Write-Host ('REVIEW POSSIBLE SECRET IN: '+$_)};throw 'Potential embedded credentials detected. Values were not printed.'}
Write-Host 'Basic Git file checks passed. This is not a complete security audit; review git diff --cached before committing.'
