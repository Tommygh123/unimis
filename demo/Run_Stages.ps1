param([ValidateSet('Register','Attendance','Results','Bill','Semester2','NextYear','RestoreSemester1')][string]$Stage='Register',[switch]$SubmitOnly)
$ErrorActionPreference='Stop'
$fixtureDir=$PSScriptRoot
Set-Location (Split-Path $fixtureDir -Parent)
$m=Get-Content (Join-Path $fixtureDir 'manifest.json') -Raw | ConvertFrom-Json
$statusText=(& $env:ComSpec /d /c 'npx.cmd supabase status -o json 2>nul' | Out-String)
if($LASTEXITCODE -ne 0 -or $statusText.IndexOf('{') -lt 0){throw 'Local Supabase status unavailable.'}
$st=$statusText.Substring($statusText.IndexOf('{')) | ConvertFrom-Json
$api=$st.API_URL; $anon=$st.ANON_KEY;if(!$anon){$anon=$st.PUBLISHABLE_KEY}
if(([Uri]$api).Host -notin @('127.0.0.1','localhost')){throw 'Localhost only.'}
function Login([string]$label){
 $person=@($m.users | Where-Object {$_.email -eq "e2e117.$label@unimis.test"})
 if($person.Count -ne 1){throw "Missing fixture login $label"}
 $payload=@{email=$person[0].email;password=$person[0].password}|ConvertTo-Json
 $session=Invoke-RestMethod -Uri "$api/auth/v1/token?grant_type=password" -Method Post -Headers @{apikey=$anon} -ContentType 'application/json' -Body $payload
 return @{apikey=$anon;Authorization="Bearer $($session.access_token)"}
}
function Rpc($headers,[string]$name,$rpcPayload){
 $result=Invoke-RestMethod -Uri "$api/rest/v1/rpc/$name" -Method Post -Headers $headers -ContentType 'application/json' -Body (ConvertTo-Json -InputObject $rpcPayload -Depth 20 -Compress)
 if($result.ok -eq $false){throw "$name returned failure: $($result.message)"}
 return $result
}
if($Stage -in @('Semester2','NextYear','RestoreSemester1')){
 $containers=@(& docker ps --filter 'name=^/supabase_db_unimis$' --format '{{.Names}}')
 if($LASTEXITCODE -ne 0 -or $containers.Count -ne 1){throw 'The local UniMIS database container must be running.'}
 $file=switch($Stage){
  'Semester2' {'Activate_2026_Semester2.sql'}
  'NextYear' {'Activate_2027_Semester1.sql'}
  'RestoreSemester1' {'Activate_2026_Semester1.sql'}
 }
 Get-Content -LiteralPath (Join-Path $fixtureDir $file) -Raw | & docker exec -i $containers[0] psql -X -U postgres -d postgres -v ON_ERROR_STOP=1
 if($LASTEXITCODE -ne 0){throw 'Test-calendar switch failed.'}
 Write-Host 'Test calendar switched. Sign out/in or reload the relevant workspace.';exit 0
}
if($Stage -eq 'Bill'){
 $h=Login 'accountant';$r=Rpc $h 'unimis_generate_period_fee_invoices' @{p_faculty_id=$null;p_department_id=$null;p_programme_id=$null;p_level=$null;p_student_type=$null}
 $r | ConvertTo-Json -Depth 10
 if($r.skipped -gt 0){throw 'Some billing rows failed; review the output.'}
 exit 0
}
$reg=Login 'registrar'
if($Stage -eq 'Register'){
 if($SubmitOnly){Write-Host 'Submission complete. Continue in Projected Results Review or your independently configured panel workflow.';return}
 foreach($person in @($m.students|Where-Object {$_.level -in @(200,300)})){
  $h=Login $person.label
  $w=Rpc $h 'unimis_student_registration_workspace' @{}
  if($w.academic_year.id -ne $m.years.'2026'){throw 'Registration automation is limited to the 2026/2027 fixture year.'}
  $pr=$w.period_registration
  if($pr.registration_status -eq 'approved'){Write-Host "$($person.label): already approved";continue}
  if($pr.registration_status -notin @('draft','rejected','submitted')){throw "Unexpected registration state for $($person.label)"}
  if($pr.registration_status -ne 'submitted'){
   $ids=@($w.courses | Where-Object {$_.is_required -and $_.course_offering_id} | ForEach-Object {$_.course_offering_id})
   if($ids.Count -ne 2){throw "Expected two fixture curriculum courses for $($person.label)"}
   $null=Rpc $h 'unimis_save_student_course_selection' @{p_period_registration_id=$pr.id;p_course_offering_ids=$ids}
   $null=Rpc $h 'unimis_submit_student_registration' @{p_period_registration_id=$pr.id}
  }
  $null=Rpc $reg 'unimis_decide_student_registration' @{p_period_registration_id=$pr.id;p_action='approve';p_notes='DEMO148: separate registrar approval'}
  Write-Host "$($person.label): student submitted; Registrar approved"
 }
 Write-Host 'Current class lists are ready. Use the Lecturer portal to test attendance or run Results next.';exit 0
}
if($Stage -eq 'Attendance'){
 $lec=Login 'lecturer'
 $w=Rpc (Login 'l300-1') 'unimis_student_registration_workspace' @{}
 $off=@($m.offerings|Where-Object {$_.year -eq 2026 -and $_.semester -eq $w.academic_period.period_number -and $_.level -eq 300 -and $_.programme_index -eq 0 -and $_.course_number -eq 1})[0]
 $register=Rpc $lec 'unimis_lecturer_class_list' @{p_course_offering_id=$off.id}
 $people=@($register.students)
 if($people.Count -eq 0){throw 'No approved class list. Run Register first.'}
 $session=Rpc $lec 'unimis_create_attendance_session' @{p_course_offering_id=$off.id;p_session_date=(Get-Date -Format 'yyyy-MM-dd');p_start_time='09:00';p_end_time='10:00';p_topic='DEMO148 attendance sample';p_venue='Test Room'}
 $records=@($people|ForEach-Object {@{student_id=$_.student_id;course_registration_id=$_.course_registration_id;status='present';remarks='Fictional attendance fixture'}})
 $null=Rpc $lec 'unimis_save_attendance' @{p_teaching_session_id=$session;p_records=$records}
 Write-Host 'One attendance session created. Repeating Attendance creates another session.';exit 0
}
if($Stage -eq 'Results'){
 $lec=Login 'lecturer';$reviewer=Login 'reviewer'
 if(-not $SubmitOnly){$reviewConfig=Rpc $reviewer 'unimis_review_setup130' @{p_inst=$m.test_institution_id};if($reviewConfig.config.enabled){$SubmitOnly=$true;Write-Host 'Committee review enabled: automation will stop at submission.'}}
 $probe=Rpc (Login 'l300-1') 'unimis_student_registration_workspace' @{}
 $sem=[int]$probe.academic_period.period_number
 if($probe.academic_year.id -ne $m.years.'2026'){throw 'Result automation is limited to 2026/2027.'}
 $offerings=@($m.offerings|Where-Object {$_.year -eq 2026 -and $_.semester -eq $sem -and $_.level -in @(200,300)})
 foreach($off in $offerings){
  $preview=Rpc $lec 'unimis_lecturer_result_preview' @{p_course_offering_id=$off.id}
  $states=@($preview.students | ForEach-Object {$_.result_status})
  if($states.Count -gt 0 -and @($states | Where-Object {$_ -ne 'published'}).Count -eq 0){Write-Host "$($off.id): already published";continue}
  if($SubmitOnly -and @($states | Where-Object {$_ -in @('submitted','approved','published')}).Count -gt 0){Write-Host "$($off.id): existing locked rows; review this offering in the lecturer/panel workspace";continue}
  if($states.Count -gt 0 -and @($states | Where-Object {$_ -notin @('submitted','approved')}).Count -eq 0){
   if(@($states|Where-Object {$_ -eq 'submitted'}).Count -gt 0){$null=Rpc $reviewer 'unimis_admin_result_action' @{p_course_offering_id=$off.id;p_action='approve';p_notes='Independent reviewer: resume DEMO148'}}
   $null=Rpc $reviewer 'unimis_admin_result_action' @{p_course_offering_id=$off.id;p_action='publish';p_notes='Resume reviewed fixture publication'}
   Write-Host "$($off.id): review/publication resumed";continue
  }
  $null=Rpc $lec 'unimis_configure_result_entry_mode' @{p_course_offering_id=$off.id;p_entry_mode='ca_exam';p_ca_weight=40;p_exam_weight=60}
  $sheet=Rpc $lec 'unimis_ca_exam_marksheet' @{p_course_offering_id=$off.id}
  $people=@($sheet.students)
  if($people.Count -eq 0){throw "No approved students in offering $($off.id). Run Register first."}
  $marks=@()
  foreach($person in $people){
   $score=if($off.course_number -eq 1){85}else{72}
   if($off.programme_index -eq 4 -and $sem -eq 2 -and $off.course_number -eq 2){$score=40}
   $marks+=@{student_id=$person.student_id;course_registration_id=$person.course_registration_id;ca_score=($score*0.4);exam_score=($score*0.6)}
  }
  $null=Rpc $lec 'unimis_save_ca_exam_scores' @{p_course_offering_id=$off.id;p_records=$marks}
  $null=Rpc $lec 'unimis_submit_course_results' @{p_course_offering_id=$off.id}
  if($SubmitOnly){Write-Host "$($off.id): entered and submitted; awaiting academic review";continue}
  $null=Rpc $reviewer 'unimis_admin_result_action' @{p_course_offering_id=$off.id;p_action='approve';p_notes='Independent reviewer: DEMO148'}
  $null=Rpc $reviewer 'unimis_admin_result_action' @{p_course_offering_id=$off.id;p_action='publish';p_notes='Publish reviewed fixture results'}
  Write-Host "$($off.level), programme $($off.programme_index+1), semester ${sem}: entered, submitted, reviewed, published"
 }
 if($SubmitOnly){Write-Host 'Submission complete. Continue in Projected Results Review or your independently configured panel workflow.';return}
 foreach($person in @($m.students|Where-Object {$_.level -in @(200,300)})){$null=Rpc $reg 'unimis_recalculate_student_period_results' @{p_student_id=$person.student_id}}
 $null=Rpc $reg 'unimis_sync_academic_trails' @{p_academic_year_id=$null}
 Write-Host 'Published. Promotion and graduation decisions remain available for you to test in the UI.'
}
