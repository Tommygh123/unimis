param([Parameter(Mandatory=$true)][string]$BackupPath)
$ErrorActionPreference='Stop'
$out=[IO.Path]::GetFullPath($BackupPath).TrimEnd([IO.Path]::DirectorySeparatorChar)
if(!(Test-Path -LiteralPath $out -PathType Container)){throw 'Backup folder not found.'}
foreach($name in @('unimis_database.dump','database_roles.sql','project-private.zip','environment.json')){
 $p=Join-Path $out $name
 if(!(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-Item -LiteralPath $p -Force).Length -eq 0){throw ('Required backup component missing or empty: '+$name+'. Backup not marked complete.')}
}
if(!(Test-Path -LiteralPath (Join-Path $out 'storage-files') -PathType Container)){throw 'Storage backup folder missing. Backup not marked complete.'}
$stream=[IO.File]::OpenRead((Join-Path $out 'unimis_database.dump'))
try{$header=New-Object byte[] 5;$read=$stream.Read($header,0,5);if($read -ne 5 -or [Text.Encoding]::ASCII.GetString($header) -ne 'PGDMP'){throw 'Database file is not a PostgreSQL custom-format dump.'}}finally{$stream.Dispose()}
$null=Get-Content -LiteralPath (Join-Path $out 'environment.json') -Raw | ConvertFrom-Json
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead((Join-Path $out 'project-private.zip'))
try{
 foreach($name in @('unimis/package.json','unimis/package-lock.json','unimis/supabase/config.toml')){if(!$zip.GetEntry($name)){throw ('Project ZIP component missing: '+$name)}}
 foreach($entry in $zip.Entries){if($entry.FullName.EndsWith('/')){continue};$entryStream=$entry.Open();try{$entryStream.CopyTo([IO.Stream]::Null)}finally{$entryStream.Dispose()}}
}finally{$zip.Dispose()}
$checksumPath=Join-Path $out 'checksums.csv'
$completePath=Join-Path $out 'BACKUP_COMPLETE.txt'
# Fully enumerate and hash before opening the output file. Never hash the manifest itself.
$files=@(Get-ChildItem -LiteralPath $out -File -Recurse -Force | Where-Object {$_.FullName -ne $checksumPath -and $_.FullName -ne $completePath})
$records=@($files | Get-FileHash -Algorithm SHA256 | Select-Object @{Name='File';Expression={$_.Path.Substring($out.Length+1)}},Hash)
if($records.Count -ne $files.Count){throw 'Some files were not hashed. Backup not marked complete.'}
$records | Export-Csv -LiteralPath $checksumPath -NoTypeInformation -Encoding UTF8
if(@(Import-Csv -LiteralPath $checksumPath).Count -ne $records.Count){throw 'Checksum manifest verification failed.'}
'Backup component checks and checksums completed. A full restore has not yet been tested. Keep this folder private.' | Set-Content -LiteralPath $completePath -Encoding UTF8
Write-Host ('SUCCESS. Backup finalized: '+$out)
Write-Host ('Files hashed: '+$records.Count)
Write-Host 'Copy the entire folder to restricted Google Drive, not GitHub.'
