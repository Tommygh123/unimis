$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$stage=Join-Path $root 'organize157'
$marker=Join-Path $PSScriptRoot 'PROJECT_ORGANIZED.json'
if(!(Test-Path -LiteralPath $stage)){
 if(Test-Path -LiteralPath $marker){Write-Host 'Project already organized. No files changed.';exit 0}
 throw 'organize157 payload missing. Extract the complete cleanup ZIP first.'
}
$config=Join-Path $root 'supabase\config.toml'
if(!(Test-Path -LiteralPath $config) -or [IO.File]::ReadAllText($config) -notmatch '(?m)^project_id\s*=\s*"unimis"\s*$'){throw 'Expected local UniMIS project. No files changed.'}
foreach($name in @('src','public','supabase\migrations','supabase\functions','package.json','package-lock.json')){if(!(Test-Path -LiteralPath (Join-Path $root $name))){throw ('Project component missing: '+$name)}}
if(Test-Path -LiteralPath (Join-Path $root 'demo')){
 if(Test-Path -LiteralPath $marker){
  $previous=Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
  $archiveParent=Join-Path (Split-Path $root -Parent) 'UniMIS_Archive'
  if(!$previous.archive -or !([IO.Path]::GetFullPath($previous.archive).StartsWith([IO.Path]::GetFullPath($archiveParent)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) -or !(Test-Path -LiteralPath $previous.archive)){throw 'Previous archive location could not be verified. No files changed.'}
  Move-Item -LiteralPath $stage -Destination (Join-Path $previous.archive ('repeat-payload-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')))
  Write-Host 'Project already organized. Re-extracted installer payload archived; working files unchanged.'
  exit 0
 }
 throw 'A demo folder already exists; it has not been overwritten. Review it before consolidating.'
}
$manifest=Get-Content -LiteralPath (Join-Path $stage 'manifest157.json') -Raw | ConvertFrom-Json
function Digest([string]$p){return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
foreach($entry in $manifest){if((Digest (Join-Path (Join-Path $stage 'payload') $entry.path)) -ne $entry.sha256){throw ('Payload checksum mismatch: '+$entry.path)}}
# Snapshot migration file bytes; the organizer must never change them.
$migrationBefore=@{}
foreach($f in Get-ChildItem -LiteralPath (Join-Path $root 'supabase\migrations') -File){$migrationBefore[$f.Name]=Digest $f.FullName}
$archive=Join-Path (Split-Path $root -Parent) ('UniMIS_Archive\'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $archive -Force | Out-Null
$journal=New-Object 'System.Collections.Generic.List[object]'
function ArchiveItem([string]$relative){
 $source=Join-Path $root $relative
 if(!(Test-Path -LiteralPath $source)){return}
 if((Get-Item -LiteralPath $source -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('Refusing linked archive item: '+$relative)}
 $target=Join-Path $archive $relative
 New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
 Move-Item -LiteralPath $source -Destination $target
 $journal.Add(@{from=$relative;to=$target})
 $journal | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $archive 'MOVED_FILES.json') -Encoding UTF8
}
# Back up overwritten project housekeeping files. Source, env and runtime state stay put.
foreach($entry in $manifest){
 $target=Join-Path $root $entry.path
 if(Test-Path -LiteralPath $target){
  $saved=Join-Path $archive ('previous-files\'+$entry.path)
  New-Item -ItemType Directory -Path (Split-Path $saved -Parent) -Force | Out-Null
  Copy-Item -LiteralPath $target -Destination $saved
 }
 New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
 Copy-Item -LiteralPath (Join-Path (Join-Path $stage 'payload') $entry.path) -Destination $target
 if((Digest $target) -ne $entry.sha256){throw ('Copy verification failed: '+$entry.path+'. Originals retained in '+$archive)}
}
# Keep an existing ready report and trainee assessment separate from template files.
foreach($pair in @(@('demo156\Ready_Report_156.json','demo\Ready_Report.json'),@('demo156\Training_Assessment_148.csv','demo\Training_Assessment.csv'))){
 $source=Join-Path $root $pair[0]
 if(Test-Path -LiteralPath $source){Copy-Item -LiteralPath $source -Destination (Join-Path $root $pair[1]) -Force}
}
# Only recognized historical folders are moved; unknown folders remain untouched.
$known=@('test-data','test-data117','test-data124','test-data130','test-data131','test-data132','test-data133','test-data134','test-data135','test-data136','test-data137','test-data138','test-data139','test-data140','test-data141','test-data142','test-data143','test-data144','test-data145','demo148','demo156','cleanup146','cleanup147','repair154','accounts155','recovery154-backups','module152','operator151','preview125','update150C')
foreach($name in $known){ArchiveItem $name}
foreach($name in @('src.zip','supabase.zip','ACCOUNTS_REPORTS_INSTALL.txt','END_TO_END_INSTALL_117.txt','INSTALLER_FIX_117A.txt','CHECK_NEW_PC.ps1','NEW_PC_CHECK.txt','RECOVERY_START_HERE.txt','RECOVERY_FILE_MANIFEST.json','apply_payment_sequence_fix.ps1')){ArchiveItem $name}
foreach($name in @('supabase\optional-demo','supabase\optional-demo154','supabase\manual-maintenance154','supabase\snippets')){ArchiveItem $name}
foreach($f in Get-ChildItem -LiteralPath (Join-Path $root 'supabase\migrations') -File){if(!$migrationBefore.ContainsKey($f.Name) -or (Digest $f.FullName) -ne $migrationBefore[$f.Name]){throw ('Migration changed unexpectedly: '+$f.Name)}}
if(@(Get-ChildItem -LiteralPath (Join-Path $root 'supabase\migrations') -File).Count -ne $migrationBefore.Count){throw 'Migration count changed unexpectedly.'}
@{organized=(Get-Date -Format o);archive=$archive;migration_files=$migrationBefore.Count;database_changed=$false} | ConvertTo-Json | Set-Content -LiteralPath $marker -Encoding UTF8
# Stage payload is no longer needed in the active project. Keep it recoverable too.
ArchiveItem 'organize157'
Write-Host ('SUCCESS. Project organized: '+$root)
Write-Host ('Old files preserved in: '+$archive)
Write-Host 'Source, migrations, local environment files, current database and login credentials were not changed.'
Write-Host 'Demo preparation, when needed: powershell -NoProfile -ExecutionPolicy Bypass -File demo\Install.ps1'
Write-Host 'Use scripts\Backup_Local.ps1 before transferring to a second PC. Do not upload backups or secrets to GitHub.'
