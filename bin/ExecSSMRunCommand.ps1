<################################################################################
## Copyright(c) 2025 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ExecRunCommand.ps1
## @summary:SSM RunCommand���s�{��
##
## @since:2025/04/11
## @version:1.0
## @see:
## @parameter
##  1:AWSVM��
##  2:RunCommand���s�X�N���v�g
##
## @return:0:Success 
##         1:���̓p�����[�^�G���[
##         9:SSM RunCommand���s�G���[
##         99:Exception
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$true)][string]$EC2Name,
  [parameter(mandatory=$true)][string]$ScriptFullPath,
  [string]$RegionName,
  [switch]$Eventlog=$false,
  [switch]$Stdout=$false
)

##########################
# ���W���[���̃��[�h
##########################
Import-Module AWS.Tools.EC2
Import-Module AWS.Tools.SimpleSystemsManagement
. .\LogController.ps1
. .\AWSLogonFunction.ps1

##########################
# �Œ�l 
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
# �x���̕\���}�~
##########################
# Set-Item Env:\SuppressAWSPowerShellBreakingChangeWarnings "true"

###############################
# LogController �I�u�W�F�N�g����
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
  $Log.Info("���O�t�@�C����:$($Log.GetLogInfo())")
}

try {
  ##########################
  # AWS���O�I������
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
  # ���[�W�����̐ݒ�
  ############################
  if(-not $RegionName) {
    $RegionName = Get-DefaultAWSRegion
  }
  $Log.Info("AWS Region: $RegionName")

  ############################
  # EC2���̃`�F�b�N
  ############################
  $filter = New-Object Amazon.EC2.Model.Filter
  $filter.Name = "tag:Name"
  $filter.Values = $EC2Name

  $Instance = (Get-EC2Instance -Filter $filter).Instances
  if(-not $Instance) { 
    $Log.Error("EC2�����s���ł��B" + $EC2Name)
    exit 9
  } elseif($Instance.count -ne 1) {
    $Log.Error("Name Tag����C���X�^���XID������ł��܂���B" + $EC2Name)
    exit 9
  }

  ##############################
  # EC2�̃X�e�[�^�X�`�F�b�N
  ##############################h
  $Log.Info("SSM Snapshot Backup:Start")
  $Log.Info("$EC2Name �̃X�e�[�^�X���擾���܂��B")
  $Log.Info("Instance Id [" + $Instance.InstanceId + "] ")
  $Log.Info("Instance Type [" + $Instance.InstanceType + "] ")
  $Log.Info("���݂̃X�e�[�^�X�� [" + $Instance.State.Name.Value + "] �ł��B") 
  $CurrentState = $Instance.State.Name

  #################################################
  # RunCommand�i�V�F���X�N���v�g���s�j
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
  $Log.Info("SSM Snapshot Lotation�FComplete")
  

  #################################################
  # �G���[�n���h�����O
  #################################################
  if($ErrorFlg) {
    $Log.Error("SSM Snapshot Backup�W���u���G���[�I�����܂����B")
    exit 9
  } else {
    $Log.Info("SSM Snapshot Backup�W���u���������܂����B")
    exit 0
  }
} catch {
    $Log.Error("SSM Snapshot Backup���s���ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    exit 99
}
exit 0