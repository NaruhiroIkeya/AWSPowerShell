<################################################################################
## Copyright(c) 2025 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ExecRunCommand.ps1
## @summary:SSM RunCommand実行本体
##
## @since:2025/04/11
## @version:1.0
## @see:
## @parameter
##  1:AWSVM名
##  2:RunCommand実行スクリプト
##
## @return:0:Success 
##         1:入力パラメータエラー
##         9:SSM RunCommand実行エラー
##         99:Exception
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$EC2Name,
  [parameter(mandatory=$true)][string]$ScriptFullPath,
  [string]$RegionName,
  [switch]$Eventlog=$false,
  [switch]$Stdout=$false
)

##########################
# モジュールのロード
##########################
Import-Module AWS.Tools.EC2
Import-Module AWS.Tools.SimpleSystemsManagement
. .\LogController.ps1
. .\AWSLogonFunction.ps1

##########################
# 固定値 
##########################
[string]$CredenticialFile = "AWSCredential_Secure.xml"
[string]$CurrentState = "Online"
[bool]$ErrorFlg = $false
[int]$RetryInterval = 30
[int]$MonitoringTimeoutHour = 1

$MetadataMaintPSFullPath="C:\script\bin\SQLMetadataMaint.ps1"

$ErrorActionPreference = "Stop"
$FinishState = "Success"

##########################
# 警告の表示抑止
##########################
# Set-Item Env:\SuppressAWSPowerShellBreakingChangeWarnings "true"

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

try {
  ##########################
  # AWSログオン処理
  ##########################
  $CredenticialFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  $CredenticialFileFullPath = $CredenticialFilePath + "\" + $CredenticialFile 
  $Connect = New-Object AWSLogonFunction($CredenticialFileFullPath)
  if($Connect.Initialize($Log)) {
    if(-not $Connect.Logon()) {
      exit 9
    }
  } else {
    exit 9
  }

  ############################
  # リージョンの設定
  ############################
  if(-not $RegionName) {
    $RegionName = Get-DefaultAWSRegion
  }
  $Log.Info("AWS Region: $RegionName")

  ############################
  # EC2名のチェック
  ############################
  $filter = New-Object Amazon.EC2.Model.Filter
  $filter.Name = "tag:Name"
  $filter.Values = $EC2Name

  $Instance = (Get-EC2Instance -Filter $filter).Instances
  if(-not $Instance) { 
    $Log.Error("EC2名が不正です。" + $EC2Name)
    exit 9
  } elseif($Instance.count -ne 1) {
    $Log.Error("Name TagからインスタンスIDが特定できません。" + $EC2Name)
    exit 9
  }

  ##############################
  # EC2のステータスチェック
  ##############################h
  $Log.Info("SSM Snapshot Backup:Start")
  $Log.Info("$EC2Name のステータスを取得します。")
  $Log.Info("Instance Id [" + $Instance.InstanceId + "] ")
  $Log.Info("Instance Type [" + $Instance.InstanceType + "] ")
  $Log.Info("現在のステータスは [" + $Instance.State.Name.Value + "] です。") 
  $CurrentState = $Instance.State.Name

  #################################################
  # RunCommand（シェルスクリプト実行）
  #################################################
  $Log.Info("Execute Script:$ScriptFullPath") 
  $BackupResult = Send-SSMCommand -DocumentName AWS-RunPowerShellScript -InstanceId $($Instance.InstanceId) -Parameter @{'commands'="$ScriptFullPath";}
  do {
    Start-Sleep -Seconds $RetryInterval
    $JobState = (Get-SSMCommand -CommandId $BackupResult.CommandId).Status.Value
    $JobOutput = (Get-SSMCommandInvocation -CommandId $BackupResult.CommandId -Detail $true).CommandPlugins.Output
  } While(!(@("Cancelled", "Success", "Failed") -contains $JobState))
  if("Failed" -eq $JobState) {
    $Log.Error("Execute Script Error:$ScriptFullPath")
    exit 9
  } elseif($($JobOutput | Select-String "-----ERROR-----")) {
    $Log.Error("`n" + $($JobOutput | Select-String "-----ERROR-----"))
    exit 9
  } else {
    $Log.Info("`n" + $JobOutput)
  }
  $Log.Info("SSM Snapshot Lotation：Complete")
  

  #################################################
  # エラーハンドリング
  #################################################
  if($ErrorFlg) {
    $Log.Error("SSM Snapshot Backupジョブがエラー終了しました。")
    exit 9
  } else {
    $Log.Info("SSM Snapshot Backupジョブが完了しました。")
    exit 0
  }
} catch {
    $Log.Error("SSM Snapshot Backup実行中にエラーが発生しました。")
    $Log.Error($_.Exception)
    exit 99
}
exit 0