# Deletes everything deploy.ps1 created, including all files in the bucket.
param(
    [string]$AwsProfile = "ccog-personal",
    [string]$Region = "us-east-1"
)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\common.ps1"

Write-Host "Deleting resources in account $AccountId ($Region)"

if (Test-Aws s3api head-bucket --bucket $BucketName) {
    Write-Host "- bucket $BucketName and its contents"
    Invoke-Aws s3 rb "s3://$BucketName" --force | Out-Null
}
if (Test-Aws lambda get-function --function-name $FunctionName) {
    Write-Host "- function $FunctionName"
    Invoke-Aws lambda delete-function --function-name $FunctionName
}
if (Test-Aws logs describe-log-streams --log-group-name $LogGroup --max-items 1) {
    Write-Host "- log group $LogGroup"
    Invoke-Aws logs delete-log-group --log-group-name $LogGroup
}
if (Test-Aws iam get-role --role-name $RoleName) {
    Write-Host "- role $RoleName"
    Test-Aws iam delete-role-policy --role-name $RoleName `
        --policy-name "s3-input-read-output-write" | Out-Null
    Invoke-Aws iam detach-role-policy --role-name $RoleName `
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    Invoke-Aws iam delete-role --role-name $RoleName
}
Write-Host "Teardown complete."
