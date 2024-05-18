<################################################################################
## Copyright(c) 2024 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ConvertSecretKey2SecureString.ps1
## @summary:Convert Service Principal Secret Key to SecureString
##
## @since:2020/05/01
## @version:1.0
## @see:
## @parameter
##  1:標準出力
##
## @return:0:Success 1:パラメータエラー 2:Az command実行エラー 9:Exception
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [switch]$Eventlog=$false,
  [switch]$Stdout
)

##########################
# モジュールのロード
##########################
. .\LogController.ps1
. .\AWSLogonFunction.ps1

##########################
# 固定値 
##########################
[string]$CredenticialFile = "AWSCredential.xml"
[string]$SecureCredenticialFile = "AWSCredential_Secure.xml"
[int]$SaveDays = 7

##########################
# 警告の表示抑止
##########################
# Set-Item Env:\SuppressAWSPowerShellBreakingChangeWarnings "true"

###############################
# LogController オブジェクト生成
###############################
if($Stdout) {
  $Log = New-Object LogController($true, (Get-ChildItem $MyInvocation.MyCommand.Path).Name)
} else {
  $LogFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve
  if($MyInvocation.ScriptName -eq "") {
    $LogBaseName = (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName
  } else {
    $LogBaseName = (Get-ChildItem $MyInvocation.ScriptName).BaseName
  }
  $LogFileName = $LogBaseName + ".log"
  $Log = New-Object LogController($(Join-Path -Path $LogFilePath -ChildPath $LogFileName), $false, $true, $LogBaseName, $false)
  $Log.DeleteLog($SaveDays)
  $Log.Info("ログファイル名:$($Log.GetLogInfo())")
}

try {
  ##########################
  # AWSログオン処理
  ##########################
  $Connect = New-Object AWSLogonFunction($(Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve), $CredenticialFile)
  $Connect.SetAWSCredential($SecureCredenticialFile) 
  
  $Log.Info("ログオンテストを実施します。")
  $Connect = New-Object AWSLogonFunction($(Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve), $SecureCredenticialFile)
  if($Connect.Initialize($Log)) {
    if(-not $Connect.Logon()) {
      exit 9
    }
  } else {
    exit 9
  }
} catch {
    $Log.Error("ログオンテスト中にエラーが発生しました。")
    $Log.Error($_.Exception)
    return $false
}
exit 0