param(
  [string]$TerraformDir = "terraform",
  [string]$AwsRegion,
  [string]$OdooDbUser = "odoo_admin",
  [Parameter(Mandatory = $true)][string]$OdooDbPassword,
  [string]$MoodleDbUser = "moodle_admin",
  [Parameter(Mandatory = $true)][string]$MoodleDbPassword,
  [string]$MoodleDbName = "moodledb"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$k8sDir = Join-Path $repoRoot "k8s"
$terraformPath = if ([System.IO.Path]::IsPathRooted($TerraformDir)) {
  $TerraformDir
}
else {
  Join-Path $repoRoot $TerraformDir
}

Write-Host "Reading Terraform outputs..."
$clusterName = terraform -chdir="$terraformPath" output -raw eks_cluster_name
$odooDbEndpoint = terraform -chdir="$terraformPath" output -raw odoo_rds_endpoint
$moodleDbEndpoint = terraform -chdir="$terraformPath" output -raw moodle_rds_endpoint
$efsId = terraform -chdir="$terraformPath" output -raw efs_id
$efsAccessPointId = terraform -chdir="$terraformPath" output -raw efs_odoo_access_point_id

$odooDbHost = ($odooDbEndpoint -split ":")[0]
$moodleDbHost = ($moodleDbEndpoint -split ":")[0]

if (-not $AwsRegion) {
  $AwsRegion = terraform -chdir="$terraformPath" output -raw aws_region
}

Write-Host "Updating kubeconfig for cluster $clusterName in $AwsRegion..."
aws eks update-kubeconfig --name $clusterName --region $AwsRegion | Out-Null

$tmpDir = Join-Path $env:TEMP ("esm-k8s-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmpDir | Out-Null
Copy-Item -Path (Join-Path $k8sDir "*") -Destination $tmpDir -Recurse -Force

$replacements = @{
  "__ODOO_DB_HOST__" = $odooDbHost
  "__ODOO_DB_USER__" = $OdooDbUser
  "__ODOO_DB_PASSWORD__" = $OdooDbPassword
  "__MOODLE_DB_HOST__" = $moodleDbHost
  "__MOODLE_DB_USER__" = $MoodleDbUser
  "__MOODLE_DB_NAME__" = $MoodleDbName
  "__MOODLE_DB_PASSWORD__" = $MoodleDbPassword
  "__EFS_ID__" = $efsId
  "__EFS_ACCESS_POINT_ID__" = $efsAccessPointId
}

Get-ChildItem -Path $tmpDir -Recurse -File -Include *.yaml,*.yml | ForEach-Object {
  $content = Get-Content $_.FullName -Raw
  foreach ($pair in $replacements.GetEnumerator()) {
    $content = $content.Replace($pair.Key, $pair.Value)
  }
  Set-Content -Path $_.FullName -Value $content
}

Write-Host "Applying Kubernetes manifests..."
kubectl apply -k $tmpDir
kubectl get pods -n esm

Write-Host "Done."
Write-Host "Temporary rendered manifests: $tmpDir"
