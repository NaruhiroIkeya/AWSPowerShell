<################################################################################
## Copyright(c) 2024 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:RemoveS3Objects.ps1
## @summary:Remove S3 Objects
##
## @since:2024/05/16
## @version:1.0
## @see:
## @parameter
##  1:バケット名
##
## @return:0:Success 9:エラー終了 / 99:Exception
################################################################################>

##########################
## パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$BucketName,
  [parameter(mandatory=$true)][string]$KeyPrefix,
  [parameter(mandatory=$true)][int]$Term,
  [string]$RegionName,
  [switch]$Eventlog=$false,
  [switch]$Stdout=$false
)

##########################
## モジュールのロード
##########################
. .\LogController.ps1
. .\AWSLogonFunction.ps1

##########################
# 固定値 
##########################
[string]$CredenticialFile = "AzureCredential_Secure.xml"
[bool]$ErrorFlg = $false
$ErrorActionPreference = "Stop"

##########################
## 警告の表示抑止
##########################
## Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

###############################
# LogController オブジェクト生成
###############################
if($Stdout -and $Eventlog) {
  $Log = New-Object LogController($true, (Get-ChildItem $MyInvocation.MyCommand.Path).Name)
} elseif($Stdout) {
  $Log = New-Object LogController
} else {
  $LogFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve
  if($MyInvocation.ScriptName -eq "") {
    $LogBaseName = (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName
  } else {
    $LogBaseName = (Get-ChildItem $MyInvocation.ScriptName).BaseName
  }
  $LogFileName = $LogBaseName + ".log"
  $Log = New-Object LogController($($LogFilePath + "\" + $LogFileName), $false, $true, $LogBaseName, $false)
  $Log.DeleteLog($SaveDays)
  $Log.Info("ログファイル名:$($Log.GetLogInfo())")
}

##########################
# パラメータチェック
##########################
if($Term -le 0) {
  $Log.Info("保持日数は1以上を設定してください。")
  exit 1
}

if(-not $RegionName) {
  $RegionName = Get-DefaultAWSRegion
}
<#
try {
  ##########################
  # AWSログオン処理
  ##########################
  $CredenticialFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  $CredenticialFileFullPath = "$CredenticialFilePath)\$($CredenticialFile)" 
  $Connect = New-Object AzureLogonFunction($CredenticialFileFullPath)
  if($Connect.Initialize($Log)) {
    if(-not $Connect.Logon()) {
      exit 9
    }
  } else {
    exit 9
  }

  $S3Bucket = Get-S3Bucket -BucketName $BucketName -Region $RegionName
  if ($S3Bucket) {
    $S3Objects = Get-S3Object -BucketName $S3Bucket.BucketName -KeyPrefix $KeyPrefix | Where-Object {$_.LastModified -gt  ((get-Date).AddDays(-1 * $Term)).ToString("yyyy/MM/dd hh:mm:ss")}
    foreach ($Obj in $S3Objects) {
      $Log.Info("$Obj を削除します。")
      Remove-S3Object -BucketName $BacketName -Key $Obj.Key -Force
    } 
  } else {
    $Log.Error("S3バケットが存在しません。")
    exit 1
  }
} catch {
  $this.Log.Error("処理中にエラーが発生しました。")
  $this.Log.Error($_.Exception)
  exit 1
}
#>
exit 0