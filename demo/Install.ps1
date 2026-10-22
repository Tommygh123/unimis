param([switch]$SeedOnly)
$ErrorActionPreference='Stop'
$fixture148=$PSScriptRoot
$config156=Join-Path (Split-Path $fixture148 -Parent) 'supabase\config.toml'
if([IO.File]::ReadAllText($config156) -notmatch '(?m)^project_id\s*=\s*"unimis"\s*$'){throw 'This installer supports local project unimis only.'}
Set-Location (Split-Path $fixture148 -Parent)
$m148=Get-Content -LiteralPath (Join-Path $fixture148 'manifest.json') -Raw | ConvertFrom-Json
function Docker148([string[]]$DockerArgs){$previous148=$ErrorActionPreference;$ErrorActionPreference='Continue';$lines148=& docker @DockerArgs 2>&1;$exit148=$LASTEXITCODE;$ErrorActionPreference=$previous148;if($exit148 -ne 0){throw (($lines148|Out-String).Trim())};return (($lines148|Out-String).Trim())}
function Sql148([string]$Query){return (Docker148 @('exec','supabase_db_unimis','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-tAq','-c',$Query))}
function File148([string]$File){Docker148 @('cp',(Join-Path $fixture148 $File),('supabase_db_unimis:/tmp/'+$File)) | Out-Null;Write-Host (Docker148 @('exec','supabase_db_unimis','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-f',('/tmp/'+$File)))}
function Fingerprint148{Docker148 @('cp',(Join-Path $fixture148 'Source_Fingerprint.sql'),'supabase_db_unimis:/tmp/Source_Fingerprint.sql') | Out-Null;return (Docker148 @('exec','supabase_db_unimis','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-tAq','-f','/tmp/Source_Fingerprint.sql'))}
# Fixed known local database container; no network service credentials are printed.
$before148=Fingerprint148
$statusText156=(& $env:ComSpec /d /c 'npx.cmd supabase status -o json 2>nul' | Out-String)
if($LASTEXITCODE -ne 0 -or $statusText156.IndexOf('{') -lt 0){throw 'Local UniMIS status unavailable.'}
$status156=$statusText156.Substring($statusText156.IndexOf('{')) | ConvertFrom-Json
$key148=$status156.SERVICE_ROLE_KEY
$api148=$status156.API_URL
if(!$key148 -or !$api148 -or ([Uri]$api148).Host -notin @('localhost','127.0.0.1') -or ([Uri]$api148).Scheme -ne 'http'){throw 'Local UniMIS API/service credentials unavailable.'}
$headers148=@{apikey=$key148;Authorization=('Bearer '+$key148);'x-upsert'='true'}
Invoke-RestMethod -Uri "$api148/storage/v1/bucket/admission-documents" -Headers $headers148 -Method Get | Out-Null
# Reject uploads outside the fixed fictional school before any seed writes.
foreach($up156 in $m148.uploads){
 if($up156.bucket -ne 'admission-documents' -or !$up156.path.StartsWith('bf51a84f-2745-5986-99df-96e34b584049/') -or !(Test-Path -LiteralPath (Join-Path $fixture148 $up156.file))){throw 'Missing or incorrectly scoped demo asset; seed not run.'}
}
$backup156=Join-Path $fixture148 ('backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $backup156 -Force | Out-Null
Docker148 @('exec','supabase_db_unimis','pg_dump','-U','postgres','-d','postgres','-Fc','-f','/tmp/unimis_before_demo156.dump') | Out-Null
Docker148 @('exec','supabase_db_unimis','pg_restore','--list','/tmp/unimis_before_demo156.dump') | Out-Null
Docker148 @('cp','supabase_db_unimis:/tmp/unimis_before_demo156.dump',(Join-Path $backup156 'unimis_before_demo156.dump')) | Out-Null
Write-Host ('Database snapshot saved before demo preparation: ' + $backup156)
File148 'Seed.sql' 
foreach($upload148 in $m148.uploads){$local148=Join-Path $fixture148 $upload148.file;Invoke-RestMethod -Uri "$api148/storage/v1/object/$($upload148.bucket)/$($upload148.path)" -Headers $headers148 -Method Post -ContentType $upload148.mime -InFile $local148 | Out-Null}
File148 'Verify.sql'
if(!$SeedOnly){
 File148 'Activate_2026_Semester1.sql'
 foreach($stage148 in @('Register','Bill','Attendance')){if($stage148 -eq 'Attendance' -and [int](Sql148 "select count(*) from public.teaching_sessions where institution_id='bf51a84f-2745-5986-99df-96e34b584049' and topic='DEMO148 attendance sample';") -gt 0){Write-Host 'Prepared attendance already exists; retaining it.';continue};& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture148 'Run_Stages.ps1') -Stage $stage148;if($LASTEXITCODE -ne 0){throw ('Preparation stopped at '+$stage148+'. Fixtures remain; fix the error and rerun.')}}
 & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture148 'Run_Stages.ps1') -Stage Results -SubmitOnly
 if($LASTEXITCODE -ne 0){throw 'Results submission preparation failed. No results were automatically approved.'}
 # Samples post through the actual payment RPC, including ledger/receipt generation.
 $loginBody148=@{email='e2e117.accountant@unimis.test';password='UniMIS117!Test'}|ConvertTo-Json
 $session148=Invoke-RestMethod -Uri "$api148/auth/v1/token?grant_type=password" -Headers @{apikey=$key148} -Method Post -ContentType 'application/json' -Body $loginBody148
 $financeHeaders148=@{apikey=$key148;Authorization=('Bearer '+$session148.access_token)}
 $current148=$m148.periods.'2026-1'
 if(!$current148){$current148=Sql148 "select id from public.academic_periods where institution_id='bf51a84f-2745-5986-99df-96e34b584049' and is_current limit 1;"}
 $invoiceJson148=Sql148 "select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select id,balance,student_id from public.student_invoices where institution_id='bf51a84f-2745-5986-99df-96e34b584049' and academic_period_id='$current148' and status<>'cancelled' order by student_id,id limit 3)x;"
 $invoiceParsed148=ConvertFrom-Json $invoiceJson148
 $invoices148=@();foreach($invoiceItem148 in $invoiceParsed148){$invoices148+=$invoiceItem148}
 for($index148=0;$index148 -lt $invoices148.Count;$index148++){
  $reference148='DEMO148-PAY-'+($index148+1)
  if([int](Sql148 "select count(*) from public.student_payments where institution_id='bf51a84f-2745-5986-99df-96e34b584049' and payment_reference='$reference148';") -gt 0){continue}
  if([decimal]$invoices148[$index148].balance -le 0){continue}
  $fractions156=@([decimal]0.5,[decimal]1.0,[decimal]0.7)
  $fraction148=[decimal]$fractions156[$index148]
  $balance156=[decimal]$invoices148[$index148].balance
  $amount156=[Math]::Round(($balance156 * $fraction148),2)
  $payment148=@{invoice_id=$invoices148[$index148].id;amount=$amount156;payment_method='cash';reference=$reference148;notes='Fictional demo payment; no external money moved'}
  Invoke-RestMethod -Uri "$api148/rest/v1/rpc/unimis_record_student_payment" -Headers $financeHeaders148 -Method Post -ContentType 'application/json' -Body (@{p_payment=$payment148}|ConvertTo-Json -Depth 8) | Out-Null
 }
 # Clear the academically eligible final-year student's billed balance for the graduation demo.
 $clearParsed148=ConvertFrom-Json (Sql148 "select coalesce(jsonb_agg(jsonb_build_object('id',id,'balance',balance)),'[]') from public.student_invoices where institution_id='bf51a84f-2745-5986-99df-96e34b584049' and student_id='88077e7f-c3c9-5c03-98ab-70316125eec4' and balance>0 and status<>'cancelled';")
 $clearInvoices148=@();foreach($clearItem148 in $clearParsed148){$clearInvoices148+=$clearItem148}
 foreach($clearInvoice148 in $clearInvoices148){
  $clearPayment148=@{invoice_id=$clearInvoice148.id;amount=[decimal]$clearInvoice148.balance;payment_method='cash';reference=('DEMO148-CLEAR-'+$clearInvoice148.id);notes='Fictional full settlement for eligible graduation case'}
  Invoke-RestMethod -Uri "$api148/rest/v1/rpc/unimis_record_student_payment" -Headers $financeHeaders148 -Method Post -ContentType 'application/json' -Body (@{p_payment=$clearPayment148}|ConvertTo-Json -Depth 8) | Out-Null
 }

}
$after148=Fingerprint148
if($before148 -ne $after148){throw 'Original school fingerprint changed. Stop and report this before demonstrations.'}
File148 'Verify.sql'
$ready148=Sql148 "select jsonb_build_object('school','UniMIS Demonstration & Training - 148','students',(select count(*) from public.students where institution_id='bf51a84f-2745-5986-99df-96e34b584049'),'published_results',(select count(*) from public.course_results where institution_id='bf51a84f-2745-5986-99df-96e34b584049' and result_status='published'),'submitted_results',(select count(*) from public.course_results where institution_id='bf51a84f-2745-5986-99df-96e34b584049' and result_status='submitted'),'attendance_records',(select count(*) from public.student_attendance where institution_id='bf51a84f-2745-5986-99df-96e34b584049'),'invoices',(select count(*) from public.student_invoices where institution_id='bf51a84f-2745-5986-99df-96e34b584049'),'completed_payments',(select count(*) from public.student_payments where institution_id='bf51a84f-2745-5986-99df-96e34b584049' and status='completed'));"
$ready148 | Set-Content -LiteralPath (Join-Path $fixture148 'Ready_Report.json') -Encoding UTF8
Write-Host $ready148
$key148=$null;$headers148.Clear();$financeHeaders148=$null;$session148=$null
Write-Host 'SUCCESS: UniMIS Demonstration & Training - 148. Source school unchanged. Any separately saved baseline remains untouched.'
Write-Host 'Sign out and use demo\Credentials.csv. Use your Two Phase Demonstration Guide 149.'
Write-Host 'Ready mode: approved current class registrations, saved attendance, invoices and submitted results. Results await human review.'
