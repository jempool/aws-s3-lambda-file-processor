# Shared settings and helpers, dot-sourced by deploy.ps1, demo.ps1 and teardown.ps1.

$RepoRoot     = Split-Path -Parent $PSScriptRoot
$BuildDir     = Join-Path $RepoRoot "build"
$FunctionName = "s3-file-processor"
$RoleName     = "s3-file-processor-role"
$LogGroup     = "/aws/lambda/$FunctionName"

# Runs the AWS CLI against the chosen profile/region and stops the script on failure.
function Invoke-Aws {
    $output = & aws @args --profile $AwsProfile --region $Region
    if ($LASTEXITCODE -ne 0) { throw "AWS CLI failed: aws $($args -join ' ')" }
    $output
}

# Returns $true when the AWS CLI call succeeds; output and errors are discarded.
# Used for "does it exist?" checks and calls that may legitimately fail.
function Test-Aws {
    # Windows PowerShell 5.1 turns redirected native stderr into errors; don't stop on them here.
    $ErrorActionPreference = "Continue"
    & aws @args --profile $AwsProfile --region $Region 2>$null | Out-Null
    $LASTEXITCODE -eq 0
}

# Writes UTF-8 without BOM, which the AWS CLI's file:// loader expects.
function Write-BuildFile([string]$Name, [string]$Content) {
    New-Item -ItemType Directory -Force $BuildDir | Out-Null
    $path = Join-Path $BuildDir $Name
    [IO.File]::WriteAllText($path, $Content)
    "file://$path"
}

$AccountId  = Invoke-Aws sts get-caller-identity --query Account --output text
$BucketName = "ccog-file-processor-$AccountId"
