<################################################################################
## Copyright(c) 2024 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:EC2BootController.ps1
## @summary:AWS EC2 Boot / Shutdown Controller
##
## @since:2024/05/19
## @version:1.0
## @see:
## @parameter
##  1:EC2名
##  2:リージョン名
##  3:起動処理モード
##  4:停止処理モード
##  5:イベントログ出力
##  6:標準出力
##
## @return:0:Success 1:パラメータエラー 2:Az command実行エラー 9:Exception
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$EC2Name,
  [string]$RegionName,
  [switch]$Boot,
  [switch]$Shutdown,
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
[bool]$ErrorFlg = $false
[int]$SaveDays = 7
[int]$RetryInterval = 15
$ErrorActionPreference = "Stop"

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
if(-not ($Boot -xor $Shutdown)) {
  $Log.Error("-Boot / -Shutdown 何れかのオプションを設定してください。")
  exit 9
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

  if($Boot) {
    ##############################
    # EC2の起動
    ##############################
    if($Instance.State.Name -eq "stopped") { 
      $Log.Info("EC2を起動します。")
      $Result = Start-EC2Instance -InstanceId $Instance.InstanceId
      if($Result) {
        while ((Get-EC2InstanceStatus -IncludeAllInstance $true -InstanceId $Instance.InstanceId).InstanceState.Name.Value -ne "running") {
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
  } elseif($Shutdown) {
    ##############################
    # EC2の停止
    ##############################
    if($Instance.State.Name -eq "running") { 
      $Log.Info("EC2を停止します。")
      $Result = Stop-EC2Instance -InstanceId $Instance.InstanceId
      if($Result) {
        while ((Get-EC2InstanceStatus -IncludeAllInstance $true -InstanceId $Instance.InstanceId).InstanceState.Name.Value -ne "stopped") {
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
      exit 0
    }
  } else {
    $Log.Error("-Boot / -Shutdown 何れかのオプションを設定してください。")
    exit 9
  }
  #################################################
  # エラーハンドリング
  #################################################
} catch {
    $Log.Error("EC2の起動/停止処理中にエラーが発生しました。")
    $Log.Error($_.Exception)
    exit 9
}
exit 0