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
##  1:EC2��
##  2:���[�W������
##  3:�N���������[�h
##  4:��~�������[�h
##  5:�C�x���g���O�o��
##  6:�W���o��
##
## @return:0:Success 1:�p�����[�^�G���[ 2:Az command���s�G���[ 9:Exception
################################################################################>

##########################
# �p�����[�^�ݒ�
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
# ���W���[���̃��[�h
##########################
Import-Module AWS.Tools.EC2
. .\LogController.ps1
. .\AWSLogonFunction.ps1

##########################
# �Œ�l 
##########################
[string]$CredenticialFile = "AWSCredential_Secure.xml"
[bool]$ErrorFlg = $false
[int]$SaveDays = 7
[int]$RetryInterval = 15
$ErrorActionPreference = "Stop"

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

##########################
# �p�����[�^�`�F�b�N
##########################
if(-not ($Boot -xor $Shutdown)) {
  $Log.Error("-Boot / -Shutdown ���ꂩ�̃I�v�V������ݒ肵�Ă��������B")
  exit 9
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
  $Log.Info("$EC2Name �̃X�e�[�^�X���擾���܂��B")
  $Log.Info("Instance Id [" + $Instance.InstanceId + "] ")
  $Log.Info("Instance Type [" + $Instance.InstanceType + "] ")
  $Log.Info("���݂̃X�e�[�^�X�� [" + $Instance.State.Name.Value + "] �ł��B")

  if($Boot) {
    ##############################
    # EC2�̋N��
    ##############################
    if($Instance.State.Name -eq "stopped") { 
      $Log.Info("EC2���N�����܂��B")
      $Result = Start-EC2Instance -InstanceId $Instance.InstanceId
      if($Result) {
        while ((Get-EC2InstanceStatus -IncludeAllInstance $true -InstanceId $Instance.InstanceId).InstanceState.Name.Value -ne "running") {
          $Log.Info("Waiting for our instance to reach the state of running...")
          Start-Sleep -Seconds $RetryInterval
        }
      } else {
        $Log.Info("EC2�N���W���u���s�Ɏ��s���܂����B")
        exit 9
      }
      $Log.Info("EC2�N���W���u���������܂����B")
    } else {
      $Log.Info("EC2�N���������L�����Z�����܂��B���݂̃X�e�[�^�X�� [" + $Instance.State.Name + "] �ł��B")
      exit 0
    }
  } elseif($Shutdown) {
    ##############################
    # EC2�̒�~
    ##############################
    if($Instance.State.Name -eq "running") { 
      $Log.Info("EC2���~���܂��B")
      $Result = Stop-EC2Instance -InstanceId $Instance.InstanceId
      if($Result) {
        while ((Get-EC2InstanceStatus -IncludeAllInstance $true -InstanceId $Instance.InstanceId).InstanceState.Name.Value -ne "stopped") {
          $Log.Info("Waiting for our instance to reach the state of stopped...")
          Start-Sleep -Seconds $RetryInterval
        }
      } else {
        $Log.Info("EC2��~�W���u���s�Ɏ��s���܂����B")
        exit 9
      }
      $Log.Info("EC2��~�W���u���������܂����B")
    } else {
      $Log.Info("EC2��~�������L�����Z�����܂��B���݂̃X�e�[�^�X�� [" + $Instance.State.Name + "] �ł��B")
      exit 0
    }
  } else {
    $Log.Error("-Boot / -Shutdown ���ꂩ�̃I�v�V������ݒ肵�Ă��������B")
    exit 9
  }
  #################################################
  # �G���[�n���h�����O
  #################################################
} catch {
    $Log.Error("EC2�̋N��/��~�������ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    exit 9
}
exit 0