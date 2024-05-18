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
##  1:�W���o��
##
## @return:0:Success 1:�p�����[�^�G���[ 2:Az command���s�G���[ 9:Exception
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [switch]$Eventlog=$false,
  [switch]$Stdout
)

##########################
# ���W���[���̃��[�h
##########################
. .\LogController.ps1
. .\AWSLogonFunction.ps1

##########################
# �Œ�l 
##########################
[string]$CredenticialFile = "AWSCredential.xml"
[string]$SecureCredenticialFile = "AWSCredential_Secure.xml"
[int]$SaveDays = 7

##########################
# �x���̕\���}�~
##########################
# Set-Item Env:\SuppressAWSPowerShellBreakingChangeWarnings "true"

###############################
# LogController �I�u�W�F�N�g����
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
  $Log.Info("���O�t�@�C����:$($Log.GetLogInfo())")
}

try {
  ##########################
  # AWS���O�I������
  ##########################
  $Connect = New-Object AWSLogonFunction($(Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve), $CredenticialFile)
  $Connect.SetAWSCredential($SecureCredenticialFile) 
  
  $Log.Info("���O�I���e�X�g�����{���܂��B")
  $Connect = New-Object AWSLogonFunction($(Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve), $SecureCredenticialFile)
  if($Connect.Initialize($Log)) {
    if(-not $Connect.Logon()) {
      exit 9
    }
  } else {
    exit 9
  }
} catch {
    $Log.Error("���O�I���e�X�g���ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    return $false
}
exit 0