<################################################################################
## Copyright(c) 2025 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ExecAWSBackupEBS.ps1
## @summary:AWS�o�b�N�A�b�v���s�{��
##
## @since:2025/02/07
## @version:1.0
## @see:
## @parameter
##  1:EBS��
##  2:Vault��
##  3:�o�b�N�A�b�v�ۊǓ���
##  4:AWS Backup �o�b�N�A�b�v�E�C���h�E
##  5:���^�[���X�e�[�^�X�i�X�i�b�v�V���b�g�҂��A�����҂��j
##
## @return:0:Success 
##         1:���̓p�����[�^�G���[
##         9:AWS Backup���s�G���[
##         99:Exception
################################################################################>

##########################
# �p�����[�^�ݒ�
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
# ���W���[���̃��[�h
##########################
##Import-Module AWS.Tools.EC2
. .\LogController.ps1
. .\AWSLogonFunction.ps1

##########################
# �Œ�l 
##########################
[string]$CredenticialFile = "AWSCredential_Secure.xml"
[string]$CurrentState = "Online"
[bool]$ErrorFlg = $false
[int]$RetryInterval = 30
[int]$MonitoringTimeoutHour = 3
$ErrorActionPreference="Stop"
$FinishState="CREATED"

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
if($StartWindow -lt 60) {
  $Log.Info("�J�n�Ԋu�i�b�j��60�ȏ��ݒ肵�Ă��������B")
  exit 1
}
if($CompleteWindow -lt 120) {
  $Log.Info("�����Ԋu�i�b�j��120�ȏ��ݒ肵�Ă��������B")
  exit 1
}
if($CycleDays -le 0) {
  $Log.Info("�o�b�N�A�b�v�ێ�������1�ȏ��ݒ肵�Ă��������B")
  exit 1
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
  # EBS���̃`�F�b�N
  ############################
  $filter = New-Object Amazon.EC2.model.Filter
  $filter.Name = "tag:Name"
  $filter.Values = $EBSName

  $Volume = (Get-EC2Volume -Filter $filter)
  if(-not $Volume) { 
    $Log.Error("EBS�����s���ł��B" + $EBSName)
    exit 9
  } elseif($Volume.count -ne 1) {
    $Log.Error("Name Tag����{�����[��ID������ł��܂���B" + $EBSName)
    exit 9
  }

  ##############################
  # EBS�̃X�e�[�^�X�`�F�b�N
  ##############################h
  $Log.Info("$EBSName �̃X�e�[�^�X���擾���܂��B")
  $Log.Info("Volume Id [" + $Volume.VolumeId + "] ")
  $Log.Info("Volume Type [" + $Volume.VolumeType + "] ")
  $Log.Info("���݂̃X�e�[�^�X�� [" + $Volume.State.Vault + "] �ł��B") 
  ##############################
  # ARN�ݒ�
  ##############################
  $AccountId=((Invoke-WebRequest "http://169.254.169.254/latest/dynamic/instance-identity/document").Content | ConvertFrom-Json).accountId
  $ResourceArn = "arn:aws:ec2:$($RegionName):$($AccountId):volume/$($Volume.VolumeId)" 
  $Log.Info("[ $ResourceArn ] ") 
  $IamRoleArn = "arn:aws:iam::$($AccountId):role/service-role/AWSBackupDefaultServiceRole"
  $Log.Info("[ $IamRoleArn ] ") 

  #################################################
  # AWS Backup(IaaS) ���s
  #################################################
  $BackupResult = $null
  #################################################
  # �N���b�V���R���V�X�e���g�o�b�N�A�b�v
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
    # �W���u�I���ҋ@(Snapshot�擾�҂�)
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
    $Log.Info("AWS Backup�W���u���I�����܂����B")
  }

  #################################################
  # �G���[�n���h�����O
  #################################################
  if($ErrorFlg) {
    $Log.Error("AWS Backup�W���u���G���[�I�����܂����B")
    exit 9
  } else {
    $Log.Info("AWS Backup�W���u���������܂����B")
    exit 0
  }
} catch {
    $Log.Error("AWS Backup���s���ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    exit 99
}
exit 0