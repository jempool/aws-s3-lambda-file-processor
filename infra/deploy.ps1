# Creates (or updates) the S3 bucket, IAM role, Lambda function and S3 trigger.
# Safe to re-run: existing resources are reused and the function code is updated.
param(
    [string]$AwsProfile = "ccog-personal",
    [string]$Region = "us-east-1"
)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\common.ps1"

Write-Host "Account $AccountId | region $Region | bucket $BucketName"

# 1. S3 bucket (new buckets block public access and encrypt with SSE-S3 by default)
if (Test-Aws s3api head-bucket --bucket $BucketName) {
    Write-Host "[1/5] Bucket exists"
} else {
    Write-Host "[1/5] Creating bucket"
    if ($Region -eq "us-east-1") {
        Invoke-Aws s3api create-bucket --bucket $BucketName | Out-Null
    } else {
        Invoke-Aws s3api create-bucket --bucket $BucketName `
            --create-bucket-configuration "LocationConstraint=$Region" | Out-Null
    }
}

# 2. IAM role: Lambda may read input/, write output/, and write its own logs
if (Test-Aws iam get-role --role-name $RoleName) {
    Write-Host "[2/5] Role exists"
} else {
    Write-Host "[2/5] Creating role"
    Invoke-Aws iam create-role --role-name $RoleName `
        --assume-role-policy-document "file://$PSScriptRoot\trust-policy.json" | Out-Null
}
Invoke-Aws iam attach-role-policy --role-name $RoleName `
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" | Out-Null
$s3Policy = Write-BuildFile "s3-access-policy.json" @"
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "s3:GetObject", "Resource": "arn:aws:s3:::$BucketName/input/*" },
    { "Effect": "Allow", "Action": "s3:PutObject", "Resource": "arn:aws:s3:::$BucketName/output/*" }
  ]
}
"@
Invoke-Aws iam put-role-policy --role-name $RoleName `
    --policy-name "s3-input-read-output-write" --policy-document $s3Policy | Out-Null
$roleArn = Invoke-Aws iam get-role --role-name $RoleName --query Role.Arn --output text

# 3. Package and deploy the Lambda function
$zip = Join-Path $BuildDir "function.zip"
New-Item -ItemType Directory -Force $BuildDir | Out-Null
Compress-Archive -Path "$RepoRoot\src\*.py" -DestinationPath $zip -Force

if (Test-Aws lambda get-function --function-name $FunctionName) {
    Write-Host "[3/5] Updating function code"
    Invoke-Aws lambda update-function-code --function-name $FunctionName `
        --zip-file "fileb://$zip" | Out-Null
    Invoke-Aws lambda wait function-updated-v2 --function-name $FunctionName
} else {
    Write-Host "[3/5] Creating function"
    # A new IAM role takes a few seconds to become assumable by Lambda; retry until it is.
    for ($attempt = 1; ; $attempt++) {
        $created = Test-Aws lambda create-function --function-name $FunctionName `
            --runtime python3.13 --handler handler.lambda_handler `
            --role $roleArn --zip-file "fileb://$zip" `
            --timeout 30 --memory-size 128 `
            --logging-config "LogFormat=JSON"
        if ($created) { break }
        if ($attempt -ge 10) { throw "Could not create Lambda function" }
        Write-Host "      waiting for IAM role to propagate ($attempt/10)..."
        Start-Sleep -Seconds 5
    }
    Invoke-Aws lambda wait function-active-v2 --function-name $FunctionName
}
$functionArn = Invoke-Aws lambda get-function --function-name $FunctionName `
    --query Configuration.FunctionArn --output text

# 4. Allow S3 (only this bucket, only this account) to invoke the function
Write-Host "[4/5] Granting S3 permission to invoke the function"
Test-Aws lambda remove-permission --function-name $FunctionName --statement-id s3-invoke | Out-Null
Invoke-Aws lambda add-permission --function-name $FunctionName `
    --statement-id s3-invoke --action lambda:InvokeFunction `
    --principal s3.amazonaws.com `
    --source-arn "arn:aws:s3:::$BucketName" --source-account $AccountId | Out-Null

# 5. Trigger only on .json files under input/ so the function's own output/ writes never re-trigger it
Write-Host "[5/5] Configuring S3 event notification"
$notification = Write-BuildFile "notification.json" @"
{
  "LambdaFunctionConfigurations": [
    {
      "Id": "process-input-json",
      "LambdaFunctionArn": "$functionArn",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": { "Key": { "FilterRules": [
        { "Name": "prefix", "Value": "input/" },
        { "Name": "suffix", "Value": ".json" }
      ] } }
    }
  ]
}
"@
Invoke-Aws s3api put-bucket-notification-configuration --bucket $BucketName `
    --notification-configuration $notification | Out-Null

Write-Host "Done. Upload a file with:"
Write-Host "  aws s3 cp sample-data\transactions.json s3://$BucketName/input/ --profile $AwsProfile"
