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
# ���W���[���̃��[�h
##########################
Import-Module AWS.Tools.EC2
. .\LogController.ps1
. .\AWSLogonFunction.ps1

##########################
# �Œ�l 
##########################
[string]$CredenticialFile = "AWSCredential_Secure.xml"
[string]$CurrentState = "Online"
[bool]$ErrorFlg = $false
[int]$RetryInterval = 15
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
  ##############################
  # ARN�ݒ�
  ##############################h
  $ResourceArn = "arn:aws:ec2:$($RegionName):$($Instance.NetworkInterfaces.OwnerId):instance/$($Instance.InstanceId)" 
  $Log.Info("[ $ResourceArn ] ") 
  $IamRoleArn = "arn:aws:iam::$($Instance.NetworkInterfaces.OwnerId):role/service-role/AWSBackupDefaultServiceRole"
  $Log.Info("[ $IamRoleArn ] ") 

  ####################################################
  # �o�b�N�A�b�v���ɒ�~��ԂłȂ���΁A�C���X�^���X���~
  ####################################################
  if($Offline) {
    ##############################
    # EC2�̒�~
    ##############################
    if("running" -eq $Instance.State.Name) { 
      $Log.Info("EC2���~���܂��B")
      $Result = Stop-EC2Instance -InstanceId $Instance.InstanceId
      if($Result) {
        while("stopped" -ne (Get-EC2InstanceStatus -IncludeAllInstance $true -InstanceId $Instance.InstanceId).InstanceState.Name.Value) {
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
    ##$Log.Info("[ Windows: $Windows ] ") 
    ##$Log.Info("[ Offline: $Offline ] ") 
    ##$Log.Info("[ CurrentState: $CurrentState ] ") 
    ##$Log.Info("[ $IamRoleArn ] ") 
    ##$log.Info("Start-BAKBackupJob -BackupVaultName $VaultName -Lifecycle_DeleteAfterDay $CycleDays -StartWindowMinute $StartWindow -CompleteWindowMinute $CompleteWindow -ResourceArn $ResourceArn -IamRoleArn $IamRoleArn")
    $BackupResult = Start-BAKBackupJob -BackupVaultName $VaultName -Lifecycle_DeleteAfterDay $CycleDays -StartWindowMinute $StartWindow -CompleteWindowMinute $CompleteWindow -ResourceArn $ResourceArn -IamRoleArn $IamRoleArn
  } else {
    #################################################
    # VSS�A�g�o�b�N�A�b�v
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
    # �W���u�I���ҋ@(Snapshot�擾�҂�)
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
    $Log.Info("AWS Backup�W���u���I�����܂����B")
  } else {
    $Log.Error("AWS Backup�W���u���G���[�I�����܂����B")
    $ErrorFlg = $true
  }

  ####################################################
  # �o�b�N�A�b�v���ɒ�~��ԂłȂ���΁A�C���X�^���X���N��
  ####################################################
  if($Offline -and -not ("stopped" -eq $CurrentState)) {
    ##############################
    # EC2�̋N��
    ##############################
    if("stopped" -eq $Instance.State.Name) { 
      $Log.Info("EC2���N�����܂��B")
      $Result = Start-EC2Instance -InstanceId $Instance.InstanceId
      if($Result) {
        while("running" -ne (Get-EC2InstanceStatus -IncludeAllInstance $true -InstanceId $Instance.InstanceId).InstanceState.Name.Value) {
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