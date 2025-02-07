<################################################################################
## Copyright(c) 2025 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ExecAWSBackupEBS.ps1
## @summary:AWSバックアップ実行本体
##
## @since:2025/02/07
## @version:1.0
## @see:
## @parameter
##  1:EBS名
##  2:Vault名
##  3:バックアップ保管日数
##  4:AWS Backup バックアップウインドウ
##  5:リターンステータス（スナップショット待ち、完了待ち）
##
## @return:0:Success 
##         1:入力パラメータエラー
##         9:AWS Backup実行エラー
##         99:Exception
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$EBSName,
  [parameter(mandatory=$true)][string]$VaultName,
  [parameter(mandatory=$true)][int]$CycleDays,
  [parameter(mandatory=$true)][int64]$StartWindow,
  [parameter(mandatory=$true)][int64]$CompleteWindow,
  [string]$RegionName,
  [switch]$Complete=$false,
  [switch]$Eventlog=$false,
  [switch]$Stdout=$false
)

##########################
# モジュールのロード
##########################
##Import-Module AWS.Tools.EC2
. .\LogController.ps1
. .\AWSLogonFunction.ps1

##########################
# 固定値 
##########################
[string]$CredenticialFile = "AWSCredential_Secure.xml"
[string]$CurrentState = "Online"
[bool]$ErrorFlg = $false
[int]$RetryInterval = 30
[int]$MonitoringTimeoutHour = 3
$ErrorActionPreference="Stop"
$FinishState="CREATED"

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

##########################
# パラメータチェック
##########################
if($StartWindow -lt 60) {
  $Log.Info("開始間隔（秒）は60以上を設定してください。")
  exit 1
}
if($CompleteWindow -lt 120) {
  $Log.Info("完了間隔（秒）は120以上を設定してください。")
  exit 1
}
if($CycleDays -le 0) {
  $Log.Info("バックアップ保持日数は1以上を設定してください。")
  exit 1
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
  # EBS名のチェック
  ############################
  $filter = New-Object Amazon.EC2.model.Filter
  $filter.Name = "tag:Name"
  $filter.Values = $EBSName

  $Volume = (Get-EC2Volume -Filter $filter)
  if(-not $Volume) { 
    $Log.Error("EBS名が不正です。" + $EBSName)
    exit 9
  } elseif($Volume.count -ne 1) {
    $Log.Error("Name TagからボリュームIDが特定できません。" + $EBSName)
    exit 9
  }

  ##############################
  # EBSのステータスチェック
  ##############################h
  $Log.Info("$EBSName のステータスを取得します。")
  $Log.Info("Volume Id [" + $Volume.VolumeId + "] ")
  $Log.Info("Volume Type [" + $Volume.VolumeType + "] ")
  $Log.Info("現在のステータスは [" + $Volume.State.Vault + "] です。") 
  ##############################
  # ARN設定
  ##############################
  $AccountId=((Invoke-WebRequest "http://169.254.169.254/latest/dynamic/instance-identity/document").Content | ConvertFrom-Json).accountId
  $ResourceArn = "arn:aws:ec2:$($RegionName):$($AccountId):volume/$($Volume.VolumeId)" 
  $Log.Info("[ $ResourceArn ] ") 
  $IamRoleArn = "arn:aws:iam::$($AccountId):role/service-role/AWSBackupDefaultServiceRole"
  $Log.Info("[ $IamRoleArn ] ") 

  #################################################
  # AWS Backup(IaaS) 実行
  #################################################
  $BackupResult = $null
  #################################################
  # クラッシュコンシステントバックアップ
  #################################################
  ##$log.Info("Start-BAKBackupJob -BackupVaultName $VaultName -Lifecycle_DeleteAfterDay $CycleDays -StartWindowMinute $StartWindow -CompleteWindowMinute $CompleteWindow -ResourceArn $ResourceArn -IamRoleArn $IamRoleArn")
  $BackupResult = Start-BAKBackupJob -BackupVaultName $VaultName -Lifecycle_DeleteAfterDay $CycleDays -StartWindowMinute $StartWindow -CompleteWindowMinute $CompleteWindow -ResourceArn $ResourceArn -IamRoleArn $IamRoleArn

  if($BackupResult) {
    $Log.Info("BackupJobId: $($BackupResult.BackupJobId)")
    $Log.Info("CreationDate: $($BackupResult.CreationDate) (UTC)")
    $StartDate = [DateTime]::ParseExact($($BackupResult.CreationDate), "MM/dd/yyyy HH:mm:ss", $null).ToLocalTime()
    $Log.Info("CreationDate: $StartDate (Localtime)")
    $SuspendDate = $StartDate.AddHours($MonitoringTimeoutHour)
    $Log.Info("MonitoringSuspendDate: $SuspendDate (Localtime)")
    $Log.Info("BackupJobFinishState: $FinishState")
    $JobState = (Get-BAKBackupJob $BackupResult.BackupJobId).State
    #################################################
    # ジョブ終了待機(Snapshot取得待ち)
    #################################################
    While(-1 -eq (Get-Date).CompareTo($SuspendDate)) {
      if (@("CREATED", "ABORTED", "COMPLETED", "FAILED", "EXPIRED", "PARTIAL") -contains $JobState) {
        if ($FinishState -eq $JobState) {
          $Log.Info("BackupJobState: $JobState")
          break
        } elseif (@("CREATED", "COMPLETED", "PARTIAL") -contains $JobState) {
          $Log.Info("BackupJobState: $JobState")
          break
        } else {
          $ErrorFlg = $true                
          $Log.Info("BackupJobState: $JobState")
          break
        }
      } else {
        $Log.Info("BackupJobState: $JobState")
        $Log.Info("Waiting for our backup to reach the state of created...")
        Start-Sleep -Seconds $RetryInterval
      }
      $JobState = (Get-BAKBackupJob $BackupResult.BackupJobId).State
    }
    if (-1 -ne (Get-Date).CompareTo($SuspendDate)) {
      $Log.Warn("Monitoring Timeout: $(Get-Date) (Localtime)")
      $ErrorFlg = $true
    }
    $Log.Info("AWS Backupジョブが終了しました。")
  }

  #################################################
  # エラーハンドリング
  #################################################
  if($ErrorFlg) {
    $Log.Error("AWS Backupジョブがエラー終了しました。")
    exit 9
  } else {
    $Log.Info("AWS Backupジョブが完了しました。")
    exit 0
  }
} catch {
    $Log.Error("AWS Backup実行中にエラーが発生しました。")
    $Log.Error($_.Exception)
    exit 99
}
exit 0