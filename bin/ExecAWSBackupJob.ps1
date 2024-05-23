<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ExecAWSBackupJob.ps1
## @summary:AWSバックアップ実行本体
##
## @since:2024/05/22
## @version:1.0
## @see:
## @parameter
##  1:AWSVM名
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
  [parameter(mandatory=$true)][string]$EC2Name,
  [parameter(mandatory=$true)][string]$VaultName,
  [parameter(mandatory=$true)][int]$CycleDays,
  [parameter(mandatory=$true)][int64]$StartWindow,
  [parameter(mandatory=$true)][int64]$CompleteWindow,
  [string]$RegionName,
  [switch]$Offline=$false,
  [switch]$Windows=$false,
  [switch]$Complete=$false,
  [switch]$Eventlog=$false,
  [switch]$Stdout=$false
)

##########################
# モジュールのロード
##########################
Import-Module AWS.Tools.EC2
. .\LogController.ps1
. .\AWSLogonFunction.ps1

##########################
# 固定値 
##########################
[string]$CredenticialFile = "AWSCredential_Secure.xml"
[string]$CurrentState = "Online"
[bool]$ErrorFlg = $false
[int]$RetryInterval = 15
$ErrorActionPreference="Stop"

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
  $Log.Info("$EC2Name のステータスを取得します。")
  $Log.Info("Instance Id [" + $Instance.InstanceId + "] ")
  $Log.Info("Instance Type [" + $Instance.InstanceType + "] ")
  $Log.Info("現在のステータスは [" + $Instance.State.Name.Value + "] です。") 
  $CurrentState = $Instance.State.Name
  ##############################
  # ARN設定
  ##############################h
  $ResourceArn = "arn:aws:ec2:$($RegionName):$($Instance.NetworkInterfaces.OwnerId):instance/$($Instance.InstanceId)" 
  $Log.Info("[ $ResourceArn ] ") 
  $IamRoleArn = "arn:aws:iam::$($Instance.NetworkInterfaces.OwnerId):role/service-role/AWSBackupDefaultServiceRole"
  $Log.Info("[ $IamRoleArn ] ") 

  ####################################################
  # バックアップ時に停止状態でなければ、インスタンスを停止
  ####################################################
  if($Offline) {
    ##############################
    # EC2の停止
    ##############################
    if("running" -eq $Instance.State.Name) { 
      $Log.Info("EC2を停止します。")
      $Result = Stop-EC2Instance -InstanceId $Instance.InstanceId
      if($Result) {
        while("stopped" -ne (Get-EC2InstanceStatus -IncludeAllInstance $true -InstanceId $Instance.InstanceId).InstanceState.Name.Value) {
          $Log.Info("Waiting for our instance to reach the state of stopped...")
          Start-Sleep -Seconds $RetryInterval
        }
      } else {
        $Log.Info("EC2停止ジョブ実行に失敗しました。")
        exit 9
      }
      $Log.Info("EC2停止ジョブが完了しました。")
    } else {
      $Log.Info("EC2停止処理をキャンセルします。現在のステータスは [" + $Instance.State.Name + "] です。")
    }
  }

  #################################################
  # AWS Backup(IaaS) 実行
  #################################################
  $BackupResult = $null
  if((-not $Windows) -or $Offline -or ("stopped" -eq $CurrentState)) {
    #################################################
    # クラッシュコンシステントバックアップ
    #################################################
    ##$Log.Info("[ Windows: $Windows ] ") 
    ##$Log.Info("[ Offline: $Offline ] ") 
    ##$Log.Info("[ CurrentState: $CurrentState ] ") 
    ##$Log.Info("[ $IamRoleArn ] ") 
    ##$log.Info("Start-BAKBackupJob -BackupVaultName $VaultName -Lifecycle_DeleteAfterDay $CycleDays -StartWindowMinute $StartWindow -CompleteWindowMinute $CompleteWindow -ResourceArn $ResourceArn -IamRoleArn $IamRoleArn")
    $BackupResult = Start-BAKBackupJob -BackupVaultName $VaultName -Lifecycle_DeleteAfterDay $CycleDays -StartWindowMinute $StartWindow -CompleteWindowMinute $CompleteWindow -ResourceArn $ResourceArn -IamRoleArn $IamRoleArn
  } else {
    #################################################
    # VSS連携バックアップ
    #################################################
    ##$Log.Info("[ Windows: $Windows ] ") 
    ##$Log.Info("[ Offline: $Offline ] ") 
    ##$Log.Info("[ CurrentState: $CurrentState ] ") 
    ##$Log.Info("[ $IamRoleArn ] ") 
    $options = @{WindowsVSS = "enabled"}
    ##$log.Info("Start-BAKBackupJob -BackupOption $options -BackupVaultName $VaultName -Lifecycle_DeleteAfterDay $CycleDays -StartWindowMinute $StartWindow -CompleteWindowMinute $CompleteWindow -ResourceArn $ResourceArn -IamRoleArn $IamRoleArn")
    $BackupResult = Start-BAKBackupJob -BackupOption $options -BackupVaultName $VaultName -Lifecycle_DeleteAfterDay $CycleDays -StartWindowMinute $StartWindow -CompleteWindowMinute $CompleteWindow -ResourceArn $ResourceArn -IamRoleArn $IamRoleArn
  }
  if($BackupResult) {
    $Log.Info("BackupJobId: $($BackupResult.BackupJobId)")
    $Log.Info("CreationDate: $($BackupResult.CreationDate)")
    #################################################
    # ジョブ終了待機(Snapshot取得待ち)
    #################################################
    $Log.Info("BackupJobState: $((Get-BAKBackupJob $BackupResult.BackupJobId).State)")
    if("RUNNING" -eq (Get-BAKBackupJob $BackupResult.BackupJobId).State) {
      while("CREATED" -ne (Get-BAKBackupJob $BackupResult.BackupJobId).State) {
        $Log.Info("Waiting for our backup to reach the state of created...")
        Start-Sleep -Seconds $RetryInterval
      }
    } elseif("FAILED" -eq (Get-BAKBackupJob $BackupResult.BackupJobId).State) {
      $ErrorFlg = $true
    } else {
      $Log.Info("BackupJobState: $((Get-BAKBackupJob $BackupResult.BackupJobId).State)")
    }
    $Log.Info("AWS Backupジョブが終了しました。")
  } else {
    $Log.Error("AWS Backupジョブがエラー終了しました。")
    $ErrorFlg = $true
  }

  ####################################################
  # バックアップ時に停止状態でなければ、インスタンスを起動
  ####################################################
  if($Offline -and -not ("stopped" -eq $CurrentState)) {
    ##############################
    # EC2の起動
    ##############################
    if("stopped" -eq $Instance.State.Name) { 
      $Log.Info("EC2を起動します。")
      $Result = Start-EC2Instance -InstanceId $Instance.InstanceId
      if($Result) {
        while("running" -ne (Get-EC2InstanceStatus -IncludeAllInstance $true -InstanceId $Instance.InstanceId).InstanceState.Name.Value) {
          $Log.Info("Waiting for our instance to reach the state of running...")
          Start-Sleep -Seconds $RetryInterval
        }
      } else {
        $Log.Info("EC2起動ジョブ実行に失敗しました。")
        exit 9
      }
      $Log.Info("EC2起動ジョブが完了しました。")
    } else {
      $Log.Info("EC2起動処理をキャンセルします。現在のステータスは [" + $Instance.State.Name + "] です。")
      exit 0
    }
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