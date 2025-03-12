<################################################################################
## Copyright(c) 2025 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:SQLMetadataMaint.ps1
## @summary:SSM CreateVssSnapshotメタデータメンテナンス
##
## @since:2025/02/16
## @version:1.0
## @see:
## @parameter
##  1:世代
##
## @return:0:Success 
################################################################################>

##########################################################
# パラメータ設定
##########################################################
param (
  [parameter(mandatory=$true)][int]$Generation
)

##########################################################
# アップロード先設定
##########################################################
$uploadServer = "\\172.31.39.174\Metadata"
$uploadDir = Get-Date -Format "yyyyMMdd"
$TargetFolder = "C:\ProgramData\Amazon\AwsVss\VssMetadata"
$uploadUser = ".\Administrator"
$uploadPass = 'A9NH$jU6hg!SZ6WV2;9idyqk*KIal0;C'

##########################################################
# 不要メタデータファイル削除
##########################################################
$SQLMetadataList = $(Get-Childitem C:\ProgramData\Amazon\AwsVss\VssMetadata\*SqlServerWriter.xml)| Sort-Object LastWriteTime -Descending | Select-Object FullName, Name
$BCDMetadataList = $(Get-Childitem C:\ProgramData\Amazon\AwsVss\VssMetadata\*BCD.xml)| Sort-Object LastWriteTime -Descending | Select-Object FullName, Name


foreach($SQLMetadataFile in $SQLMetadataList) { Write-Output "SqlServerWriter: $($SQLMetadataFile.Name)" }
foreach($BCDMetadataFile in $BCDMetadataList) { Write-Host "BCD: $($BCDMetadataFile.Name)" }

for($cnt = $Generation; $cnt -lt $SQLMetadataList.Count; $cnt++) {
  Write-Output "Delete Metadata File: $($SQLMetadataList[$cnt].Name)"
  Remove-Item $SQLMetadataList[$cnt].FullName -Force
}

for($cnt = $Generation; $cnt -lt $BCDMetadataList.Count; $cnt++) {
  Write-Output "Delete Metadata File: $($BCDMetadataList[$cnt].Name)"
  Remove-Item $BCDMetadataList[$cnt].FullName -Force
}


##########################################################
# アップロード用のゲスト認証Credentialを生成する
##########################################################
$secStr = ConvertTo-SecureString $uploadPass -AsPlainText -Force
$cred = New-Object System.Management.Automation.PsCredential($uploadUser, $secStr)

##########################################################
# PSドライブにマウントする
##########################################################
$psDriveName = "Z"
if(Get-PSDrive | where {$_.Name -eq $psDriveName}) {
   # エラー終了などで既に存在する場合は一旦アンマウントする
   Remove-PSDrive -Name $psDriveName
}
$uploadDrive = New-PSDrive -Name $psDriveName -PSProvider FileSystem -Root $uploadServer -Credential $cred

##########################################################
# アップロードする
##########################################################
$uploadUri = Join-Path $uploadServer $uploadDir
Robocopy $TargetFolder $uploadUri
$TargetDir=Get-ChildItem $uploadServer -Recurse | Where-Object {($_.Mode -eq "d-----")} | Sort-Object CreationTime -Descending
for($cnt = $Generation; $cnt -lt $TargetDir.Count; $cnt++) {
  Write-Output "Delete Backup Metadata File: $($TargetDir[$cnt].FullName)"
  Remove-Item $TargetDir[$cnt].FullName -Recurse -Force
}

##########################################################
# PSドライブをアンマウントする
##########################################################
Remove-PSDrive -Name $psDriveName -Force
