<################################################################################
## Copyright(c) 2025 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ReplaceDBPath.ps1
## @summary:Database ファイルパスの変更
## @sample:C:\SCripts\ReplaceDBPath.ps1 USERDB "K,j" "e,f" "k,h"
##
## @since:2025/02/16
## @version:1.0
## @see:
## @parameter
##  1:世代
##
## @return:0:Success 
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$SID_DB,
  [parameter(mandatory=$true)][string]$Source_Drive_Letters,
  [parameter(mandatory=$true)][string]$Target_Drive_Letters,
  [parameter(mandatory=$false)][string]$Remove_Drive_Letters
)

Import-Module sqlps

$ErrorActionPreference = "Stop"

$SAPDBFile_FullPath = @()
$New_SAPDBFile_FullPath = @()

try {
  $SID_DB
  $SAPDBInstance = Get-Item SQLSERVER:\SQL\$env:COMPUTERNAME\DEFAULT\Databases\$SID_DB
}
catch {
  echo "Do not found database:$SID_DB"
  exit 9
}

##########################
# ドライブ文字列チェック
##########################
$SourceDriveLetters = $Source_Drive_Letters.ToUpper() -split ",\s*"
foreach($DriveLetter in $SourceDriveLetters) {
  if((1 -ne $DriveLetter.length) -or !(Test-Path $($DriveLetter + ":"))) {
    echo "Please check source drive letter settings...: $DriveLetter"
    exit 9
  }
}

$TargetDriveLetters = $Target_Drive_Letters.ToUpper() -split ",\s*"
foreach($DriveLetter in $TargetDriveLetters) {
  if((1 -ne $DriveLetter.length) -or !(Test-Path $($DriveLetter + ":"))) {
    echo "Please check target drive letter settings...: $DriveLetter"
    exit 9
  }
}

if(-not [String]::IsNullOrEmpty($Remove_Drive_Letters)) {
  $RemoveDriveLetters = $Remove_Drive_Letters.ToUpper() -split ",\s*"
  foreach($DriveLetter in $RemoveDriveLetters) {
    if((1 -ne $DriveLetter.length) -or !(Test-Path $($DriveLetter + ":"))) {
      echo "Please check remove drive letter settings...: $DriveLetter"
      exit 9
    }
  }
}

if($SourceDriveLetters.Count -ne $TargetDriveLetters.Count) {
    echo "Please check source and target drive letter settings...: Source:$Source_Drive_Letters Target:$Target_Drive_Letters"
    exit 9
}

############################
# 移動元DBファイルPath取得
############################
$SAPDBFile_FullPath = @()
foreach($FileGroup in $SAPDBInstance.FileGroups) {
  foreach($DBFile in $FileGroup.Files) {
    if(Test-Path $DBFile.FileName) { $SAPDBFile_FullPath += $DBFile.FileName }
  }
}
############################
# 移動元DBLogファイルPath取得
############################
foreach($LogFiles in $SAPDBInstance.LogFiles) {
  if(Test-Path $DBFile.FileName) { $SAPDBFile_FullPath += $LogFiles.FileName }
}

echo $SAPDBFile_FullPath
$($SAPDBFile_FullPath -Join ",") | Out-String > $($SID_DB+"_Before_Database.csv")

##########################
# SQLServer再起動
##########################
[reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")
$ManagedComputer = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
$Svc = $ManagedComputer.Services["MSSQLSERVER"]
Write-Host "Stopping $($Svc.Name)"
$Svc.Stop()
do {
  $Svc.Refresh()
  Start-Sleep 3
} while ("Stopped" -ne $Svc.ServiceState)
Write-Host "Service $($Svc.Name) is now stopped"

Start-Sleep 10

Write-Host "Starting $($Svc.Name)"
$Svc.Start()
do {
  $Svc.Refresh()
  Start-Sleep 3
} while ("Running" -ne $Svc.ServiceState)
Write-Host "Service $($Svc.Name) is now started"
$Svc.Refresh()

##########################
# 移動元DBデタッチ
##########################
Write-Host "Detach Database:$SID_DB"
do {
  (Get-Item SQLSERVER:\SQL\\$env:COMPUTERNAME\DEFAULT).DetachDatabase($SID_DB, $false)
} while (Test-Path SQLSERVER:\SQL\$env:COMPUTERNAME\DEFAULT\Databases\$SID_DB) 

##########################
# ドライブレター更新
##########################
for($cnt=0; $cnt -lt $SourceDriveLetters.Count; $cnt++) {
  Write-Host "Remove Drive Letter:$($TargetDriveLetters[$cnt])"
  Remove-PartitionAccessPath -DriveLetter $($TargetDriveLetters[$cnt]) -AccessPath $(Join-Path $($($TargetDriveLetters[$cnt])+":") \)
  Write-Host "Change Drive Letter:$($SourceDriveLetters[$cnt]) to $($TargetDriveLetters[$cnt])"
  Set-Partition -DriveLetter $($SourceDriveLetters[$cnt]) -NewDriveLetter $($TargetDriveLetters[$cnt])
  foreach($FilePath in $SAPDBFile_FullPath) {
    if($($($SourceDriveLetters[$cnt])+":") -eq $(Split-Path -Qualifier $FilePath)) {
      $New_SAPDBFile_FullPath += Join-Path $($TargetDriveLetters[$cnt]+":") $(Split-Path -NoQualifier $FilePath)
    } else {
       continue
    }
  }
}
$New_SAPDBFile_FullPath
$($New_SAPDBFile_FullPath -Join ",") | Out-String > $($SID_DB+"_After_Database.csv")
Get-Partition | Where-Object {$_.Type -ne "Reserved" -and $_.Driveletter -ne 0} | Select-Object DriveLetter, DiskNumber, PartitionNumber, UniqueId | Sort-Object -Property DriveLetter | FT

##########################
# 移動元DBアタッチ
##########################
Write-Host "Attach Database:$SID_DB"
$DBFiles = New-Object System.Collections.Specialized.StringCollection
foreach($DBFile_FullPath in $New_SAPDBFile_FullPath) {
  if(Test-Path $DBFile_FullPath) { $DBFiles.Add($DBFile_FullPath) | Out-Null }
}
if(-not (Test-Path SQLSERVER:\SQL\$env:COMPUTERNAME\DEFAULT\Databases\$SID_DB)) {
  (Get-Item SQLSERVER:\SQL\\$env:COMPUTERNAME\DEFAULT).AttachDatabase($SID_DB, $DBFiles)
  if(Test-Path SQLSERVER:\SQL\$env:COMPUTERNAME\DEFAULT\Databases\$SID_DB) {
    Write-Host "Attach Database:$SID_DB Successful"
  }
} else {
  Write-Host "already exist database:$SID_DB"
}
Start-Sleep 10

##########################
# SQLServer再起動
##########################
[reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")
$ManagedComputer = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
$Svc = $ManagedComputer.Services["MSSQLSERVER"]
Write-Host "Stopping $($Svc.Name)"
$Svc.Stop()
do {
  $Svc.Refresh()
  Start-Sleep 3
} while ("Stopped" -ne $Svc.ServiceState)
Write-Host "Service $($Svc.Name) is now stopped"

Start-Sleep 10

Write-Host "Starting $($Svc.Name)"
$Svc.Start()
do {
  $Svc.Refresh()
  Start-Sleep 3
} while ("Running" -ne $Svc.ServiceState)
Write-Host "Service $($Svc.Name) is now started"
$Svc.Refresh()

##########################
# 不要ドライブの無効化
##########################
if(-not [String]::IsNullOrEmpty($Remove_Drive_Letters)) {
  $RemoveDriveLetters = $Remove_Drive_Letters.ToUpper() -split ",\s*"
  foreach($DriveLetter in $RemoveDriveLetters) {
    Write-Host "Remove Drive Letter:$($DriveLetter)"
    Remove-PartitionAccessPath -DriveLetter $DriveLetter -AccessPath $(Join-Path $($DriveLetter+":") \)
  }
}

##########################
# 不要ボリュームの表示
##########################
Get-Partition | Where-Object {$_.Type -ne "Reserved" -and $_.Driveletter -eq 0} | Select-Object DriveLetter, DiskNumber, UniqueId | Sort-Object -Property DiskNumber | FT
$DisableDiskInfo = Get-Partition | Where-Object {$_.Type -ne "Reserved" -and $_.Driveletter -eq 0} | Select-Object DriveLetter, DiskNumber, UniqueId | Sort-Object -Property DiskNumber
Write-Host "Please detach EBS volumes"
foreach($DiskInfo in $DisableDiskInfo) { 
  Set-Disk -IsOffline $true -Number $DiskInfo.DiskNumber
  Write-Host "$($DiskInfo.UniqueId.Substring(38,3))-$($DiskInfo.UniqueId.Substring(41,17))"
}

Remove-Item $($SID_DB+"_Before_Database.csv")
Remove-Item $($SID_DB+"_After_Database.csv")
