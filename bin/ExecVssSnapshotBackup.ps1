<################################################################################
## Copyright(c) 2025 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ExecVssSnapshotBackup.ps1
## @summary:SSM CreateVssSnapshot�o�b�N�A�b�v���s�{��
##
## @since:2025/02/16
## @version:1.0
## @see:
## @parameter
##  1:AWSVM��
##  2:�o�b�N�A�b�v�ۊǓ���
##
## @return:0:Success 
##         1:���̓p�����[�^�G���[
##         9:SSM Snapshot Backup���s�G���[
##         99:Exception
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$true)][string]$EC2Name,
  [parameter(mandatory=$true)][int]$Generation,
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

$MetadataMaintPSFullPath="C:\Scripts\SQLMetadataMaint.ps1"

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

##########################
# �p�����[�^�`�F�b�N
##########################
if($Generation -le 0) {
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
  $Log.Info("SSM Snapshot Backup:Start")
  $Log.Info("$EC2Name �̃X�e�[�^�X���擾���܂��B")
  $Log.Info("Instance Id [" + $Instance.InstanceId + "] ")
  $Log.Info("Instance Type [" + $Instance.InstanceType + "] ")
  $Log.Info("���݂̃X�e�[�^�X�� [" + $Instance.State.Name.Value + "] �ł��B") 
  $CurrentState = $Instance.State.Name

  #################################################
  # SSM Snapshot Backup(IaaS) ���s
  #################################################
  $BackupResult = $null
  $Timestamp = $(Get-Date -Format "yyyy/MM/dd-HH:mm:dd")

  # $Log.Info("Send-SSMCommand -DocumentName AWSEC2-VssInstallAndSnapshot -InstanceId $($Instance.InstanceId) -Parameter @{'ExcludeBootVolume'='True';'SaveVssMetadata'='True';'description'='VssSnapshotBackup $Timestamp';'tags'='Key=Name,Value=SQLServer Snapshot Backup;Key=BackupType,Value=SQLServerVSS'}")
  $BackupResult = Send-SSMCommand -DocumentName AWSEC2-VssInstallAndSnapshot -InstanceId $($Instance.InstanceId) -Parameter @{'ExcludeBootVolume'='True';'SaveVssMetadata'='True';'description'="VssSnapshotBackup $Timestamp";'tags'='Key=Name,Value=SQLServer Snapshot Backup;Key=BackupType,Value=SQLServerVSS'}

  if($BackupResult) {
    $Log.Info("CommandId: $($BackupResult.CommandId)")
    $Log.Info("RequestedDateTime: $($BackupResult.RequestedDateTime) (UTC)")
    $StartDate = [DateTime]::ParseExact($($BackupResult.RequestedDateTime), "MM/dd/yyyy HH:mm:ss", $null).ToLocalTime()
    $Log.Info("RequestedDateTime: $StartDate (Localtime)")
    $SuspendDate = $StartDate.AddHours($MonitoringTimeoutHour)
    $Log.Info("MonitoringSuspendDate: $SuspendDate (Localtime)")
    $Log.Info("BackupJobFinishState: $FinishState")
    $JobState = (Get-SSMCommand -CommandId $BackupResult.CommandId).Status.Value
    #################################################
    # �W���u�I���ҋ@(Snapshot�擾�҂�)
    #################################################
    While(-1 -eq (Get-Date).CompareTo($SuspendDate)) {
      $Log.Info("CommandState: $JobState")
      if(@("Cancelled", "Success") -contains $JobState) {
        break
      } elseif(@("Failed") -contains $JobState) {
        $ErrorFlg = $true
        break
      } else {
        Start-Sleep -Seconds $RetryInterval
      }
      $JobState = (Get-SSMCommand -CommandId $BackupResult.CommandId).Status.Value
    }
    if (-1 -ne (Get-Date).CompareTo($SuspendDate)) {
      $Log.Warn("Monitoring Timeout: $(Get-Date) (Localtime)")
      $ErrorFlg = $true
    }
    $Log.Info("`n" + $((Get-SSMCommandInvocation -CommandId $BackupResult.CommandId -Detail $true).CommandPlugins.Output))
  } else {
    $Log.Error("SSM Snapshot Backup:Failed")
    exit 9
  }
  $Log.Info("SSM Snapshot Backup:Finished")

  #################################################
  # ����Ǘ�
  #################################################
  $filter = New-Object Amazon.EC2.Model.Filter
  $filter.Name = "tag:BackupType"
  $filter.Values = "SQLServerVSS"

  $Log.Info("SSM Snapshot Lotation�FStart")
  $BackupList = $(Get-EC2Snapshot -Filter $filter).Description | Sort-Object -Descending | Get-Unique
  foreach($BackupItem in $BackupList) { $Log.Info("SSM Snapshot Item�F$BackupItem") }
  for($cnt = $Generation; $cnt -lt $BackupList.Count; $cnt++) {
    $Log.Info("Delete Snapshot Backups�F$($BackupList[$cnt])")
    $DeleteTargetSnapshot = Get-EC2Snapshot | ? { $_.Description -eq $($BackupList[$cnt]) }
    foreach($Snapshot in $DeleteTargetSnapshot) {
      $Log.Info("Delete Snapshot Id�F$($Snapshot.SnapshotId)")
      Remove-EC2Snapshot -SnapshotId $Snapshot.SnapshotId -Force
    }
  }
  #################################################
  # ����Ǘ�(MetaData)
  #################################################
  $BackupResult = Send-SSMCommand -DocumentName AWS-RunPowerShellScript -InstanceId $($Instance.InstanceId) -Parameter @{'commands'="$MetadataMaintPSFullPath -Generation $Generation";}
  do {
    Start-Sleep -Seconds $RetryInterval
    $JobState = (Get-SSMCommand -CommandId $BackupResult.CommandId).Status.Value
  } While(!(@("Cancelled", "Success", "Failed") -contains $JobState))
  $Log.Info("`n" + $((Get-SSMCommandInvocation -CommandId $BackupResult.CommandId -Detail $true).CommandPlugins.Output))

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