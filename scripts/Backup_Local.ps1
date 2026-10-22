param([string]$Destination)
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
if(!$Destination){$Destination=Join-Path (Split-Path $project -Parent) ('UniMIS_Backups\'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))}
$out=[IO.Path]::GetFullPath($Destination)
if($out.TrimEnd('\') -eq $project.TrimEnd('\') -or $out.StartsWith($project.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Backup destination must be outside the project.'}
if(Test-Path -LiteralPath $out){throw 'Use a new backup folder; an existing folder will not be overwritten.'}
Set-Location $project
if([IO.File]::ReadAllText((Join-Path $project 'supabase\config.toml')) -notmatch '(?m)^project_id\s*=\s*"unimis"\s*$'){throw 'Expected local UniMIS project.'}
function DockerBackup([string[]]$Arguments){$previous=$ErrorActionPreference;$ErrorActionPreference='Continue';$result=& docker @Arguments 2>&1;$exit=$LASTEXITCODE;$ErrorActionPreference=$previous;if($exit -ne 0){throw ('Docker backup step failed: '+($result|Out-String))};return ($result|Out-String).Trim()}
New-Item -ItemType Directory -Path $out | Out-Null
$meta=@{created=(Get-Date -Format o);project_id='unimis';note='Private backup contains credentials and database records. Pause writes/uploads during backup.'}
$meta.db_image=DockerBackup @('inspect','supabase_db_unimis','--format','{{.Config.Image}}')
$meta.storage_image=DockerBackup @('inspect','supabase_storage_unimis','--format','{{.Config.Image}}')
$meta.node=(& node --version | Out-String).Trim()
$cliText=(& $env:ComSpec /d /c 'npx.cmd supabase --version 2>nul' | Out-String).Trim()
if($LASTEXITCODE -ne 0){throw 'Could not record Supabase CLI version. Partial backup folder retained.'}
$meta.supabase_cli=$cliText
DockerBackup @('exec','supabase_db_unimis','pg_dump','-U','postgres','-d','postgres','-Fc','-f','/tmp/unimis_transfer.dump') | Out-Null
DockerBackup @('exec','supabase_db_unimis','pg_restore','--list','/tmp/unimis_transfer.dump') | Out-Null
DockerBackup @('cp','supabase_db_unimis:/tmp/unimis_transfer.dump',(Join-Path $out 'unimis_database.dump')) | Out-Null
DockerBackup @('exec','supabase_db_unimis','pg_dumpall','-U','postgres','--roles-only','-f','/tmp/unimis_transfer_roles.sql') | Out-Null
DockerBackup @('cp','supabase_db_unimis:/tmp/unimis_transfer_roles.sql',(Join-Path $out 'database_roles.sql')) | Out-Null
$mounts=ConvertFrom-Json (DockerBackup @('inspect','supabase_storage_unimis','--format','{{json .Mounts}}'))
$mount=@($mounts | Where-Object {$_.Destination -eq '/mnt'})
if($mount.Count -ne 1){throw 'Storage mount differs from the known /mnt layout. Partial backup retained; do not treat it as complete.'}
New-Item -ItemType Directory -Path (Join-Path $out 'storage-files') | Out-Null
DockerBackup @('cp','supabase_storage_unimis:/mnt/.',(Join-Path $out 'storage-files')) | Out-Null
# .NET ZIP includes hidden env files, unlike some Compress-Archive paths.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath=Join-Path $out 'project-private.zip'
$zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
try{
 foreach($f in Get-ChildItem -LiteralPath $project -File -Recurse -Force){
  $rel=$f.FullName.Substring($project.Length+1).Replace('\','/')
  if($rel -match '(^|/)(node_modules|dist|dist-ssr|\.git|backups)(/|$)' -or $rel -match '^supabase/(\.temp|\.branches)/'){continue}
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$f.FullName,('unimis/'+$rel),[IO.Compression.CompressionLevel]::Optimal) | Out-Null
 }
}finally{$zip.Dispose()}
$meta | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'environment.json') -Encoding UTF8
$checksumPath=Join-Path $out 'checksums.csv'
$completePath=Join-Path $out 'BACKUP_COMPLETE.txt'
$files=@(Get-ChildItem -LiteralPath $out -File -Recurse -Force | Where-Object {$_.FullName -ne $checksumPath -and $_.FullName -ne $completePath})
$records=@($files | Get-FileHash -Algorithm SHA256 | Select-Object @{Name='File';Expression={$_.Path.Substring($out.Length+1)}},Hash)
if($records.Count -ne $files.Count){throw 'Backup checksum generation incomplete.'}
$records | Export-Csv -LiteralPath $checksumPath -NoTypeInformation -Encoding UTF8
'Backup finished. Restore has not yet been tested. Keep this folder private.' | Set-Content -LiteralPath (Join-Path $out 'BACKUP_COMPLETE.txt')
Write-Host ('Backup complete: '+$out)
Write-Host 'Copy the entire folder to restricted backup storage. Do not put it in GitHub.'
