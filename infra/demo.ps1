# End-to-end demo: uploads every file in sample-data/ to input/, waits for each
# summary in output/, and saves the summaries plus the CloudWatch logs to evidence/.
param(
    [string]$AwsProfile = "ccog-personal",
    [string]$Region = "us-east-1"
)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\common.ps1"

$evidenceDir = Join-Path $RepoRoot "evidence"
$outputDir = Join-Path $evidenceDir "output"
New-Item -ItemType Directory -Force $outputDir | Out-Null

# The bucket name contains the account ID; keep it out of the committed evidence.
function Save-Redacted([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content.Replace($AccountId, "<ACCOUNT_ID>"))
}

$startMs = [DateTimeOffset]::UtcNow.AddSeconds(-5).ToUnixTimeMilliseconds()

foreach ($file in Get-ChildItem "$RepoRoot\sample-data\*.json") {
    $outputKey = "output/$($file.BaseName).summary.json"
    # Remove any previous summary so the wait below only succeeds on a fresh one.
    Invoke-Aws s3 rm "s3://$BucketName/$outputKey" | Out-Null

    Write-Host "Uploading $($file.Name) -> s3://$BucketName/input/"
    Invoke-Aws s3 cp $file.FullName "s3://$BucketName/input/$($file.Name)" | Out-Null

    Invoke-Aws s3api wait object-exists --bucket $BucketName --key $outputKey
    $local = Join-Path $outputDir "$($file.BaseName).summary.json"
    $summary = (Invoke-Aws s3 cp "s3://$BucketName/$outputKey" -) -join "`n"
    Save-Redacted $local $summary
    Write-Host "  -> $outputKey : $(($summary | ConvertFrom-Json).status)"
}

# CloudWatch delivers logs a few seconds after the invocation; poll until all runs are in.
$expectedRuns = @(Get-ChildItem "$RepoRoot\sample-data\*.json").Count
for ($attempt = 1; $attempt -le 12; $attempt++) {
    $events = (Invoke-Aws logs filter-log-events --log-group-name $LogGroup `
        --start-time $startMs --query "events[].message" --output json) -join "`n" | ConvertFrom-Json
    $finished = @($events | Where-Object { $_ -like '*"platform.report"*' }).Count
    if ($finished -ge $expectedRuns) { break }
    Start-Sleep -Seconds 5
}
$logLines = ($events | ForEach-Object { $_.Trim() }) -join ",`n  "
Save-Redacted (Join-Path $evidenceDir "cloudwatch-logs.json") "[`n  $logLines`n]`n"

Write-Host "Saved $(@($events).Count) log events and $expectedRuns summaries to evidence/"
