<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ExecAWSBackupJob.ps1
## @summary:AWS�o�b�N�A�b�v���s�{��
##
## @since:2024/05/22
## @version:1.0
## @see:
## @parameter
##  1:AWSVM��
##  2:Recovery Service�R���e�i�[��
##  3:�o�b�N�A�b�v�ۊǓ���
##  4:AWS Backup�W���u�|�[�����O�Ԋu�i�b�j
##  5:���^�[���X�e�[�^�X�i�X�i�b�v�V���b�g�҂��A�����҂��j
##
## @return:0:Success 
##         1:���̓p�����[�^�G���[
##         2:AWS Backup�W���u�Ď����f�iTake Snapshot�����j
##         9:AWS Backup���s�G���[
##         99:Exception
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$true)][string]$EC2Name,
  [parameter(mandatory=$true)][string]$VaultName,
  [parameter(mandatory=$true)][int]$CycleDays,
  [parameter(mandatory=$true)][int64]$JobTimeout,
  [string]$RegionName,
  [switch]$Offline=$false,
  [switch]$Windows=$false,
  [switch]$Complete=$false,
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
New-Variable -Name ReturnState -Value @("Take Snapshot","Transfer data to vault") -Option ReadOnly
[string]$CurrentState = "Online"
$ErrorActionPreference="Stop"

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
if($JobTimeout -le 0) {
  $Log.Info("�|�[�����O�Ԋu�i�b�j��1�ȏ��ݒ肵�Ă��������B")
  exit 1
}
if($AddDays -le 0) {
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
  $CurrentState = $Instance.State.Name
  $ARName = "arn:aws:ec2:$($RegionName):$($Instance.NetworkInterfaces.OwnerId):$($Instance.InstanceId)" 

  ####################################################
  # �o�b�N�A�b�v���ɒ�~��ԂłȂ���΁A�C���X�^���X���~
  ####################################################
  if($Offline) {
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
    }
  }

  #################################################
  # AWS Backup(IaaS) ���s
  #################################################
  $BackupResult = $null
  if((-not $Windows) -or $Offline -or ("stopped" -eq $CurrentState)) {
    #################################################
    # �N���b�V���R���V�X�e���g�o�b�N�A�b�v
    #################################################
    $BackupResult = Start-BAKBackupJob -BackupVaultName -$VaultName -Lifecycle_DeleteAfterDay $CycleDays -CompleteWindowMinuts $JobTimeOut -ResourceArn $ARName
  } else {
    #################################################
    # VSS�A�g�o�b�N�A�b�v
    #################################################
    $options = @{}
    $key = "WindowsVSS"
    $value = "enabled"
    $options.add($key, $value)
    $BackupResult = Start-BAKBackupJob -BackupOption $options -BackupVaultName $VaultName -Lifecycle_DeleteAfterDay $CycleDays -CompleteWindowMinuts $JobTimeOut -ResouceArn $ARName
  }
  if($BackupResult) {

  }

  ####################################################
  # �o�b�N�A�b�v���ɒ�~��ԂłȂ���΁A�C���X�^���X���N��
  ####################################################
  if($Offline -and -not ("stopped" -eq $CurrentState)) {
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
  }

  #################################################
  # �W���u�I���ҋ@(Snapshot�擾�҂�)
  #################################################
  $JobResult = Wait-AzRecoveryServicesBackupJob -VaultId $RecoveryServiceVault.ID -Job $Job -Timeout $JobTimeout
  $CompStatus = if($Complete) { Write-Output "1" } else { Write-Output "0" }
    While(($($JobResult.SubTasks | Where-Object {$_.Name -eq $ReturnState[$CompStatus]} | ForEach-Object {$_.Status}) -ne "Completed") -and ($JobResult.Status -ne "Failed" -and $JobResult.Status -ne "Cancelled")) {
    $Log.Info($ReturnState[$CompStatus] + "�t�F�[�Y�̊�����ҋ@���Ă��܂��B")    
    $JobResult = Wait-AzRecoveryServicesBackupJob -VaultId $RecoveryServiceVault.ID -Job $Job -Timeout $JobTimeout
  }
  if($JobResult.Status -eq "InProgress") {
    $SubTasks = $(Get-AzRecoveryServicesBackupJobDetail -VaultId $RecoveryServiceVault.ID -JobId $JobResult.JobId).SubTasks
    $Log.Info("AWS Backup�W���u�Ď��𒆒f���܂��BJob ID=" +  $JobResult.JobId)
    Foreach($SubTask in $SubTasks) {
      $Log.Info($SubTask.Name + " " +  $SubTask.Status)
    }
    exit 2
  } elseif($JobResult.Status -eq "Cancelled") {
    $SubTasks = $(Get-AzRecoveryServicesBackupJobDetail -VaultId $RecoveryServiceVault.ID -JobId $JobResult.JobId).SubTasks
    $Log.Warn("AWS Backup�W���u���L�����Z������܂����BJob ID=" +  $JobResult.JobId)
    Foreach($SubTask in $SubTasks) {
      $Log.Warn($SubTask.Name + " " +  $SubTask.Status)
    }
    exit 0
  }

  #################################################
  # �G���[�n���h�����O
  #################################################
  if($JobResult.Status -eq "Failed") {
    $Log.Error("AWS Backup�W���u���G���[�I�����܂����B")
    $Log.Error($($JobResult | Format-List | Out-String -Stream))
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