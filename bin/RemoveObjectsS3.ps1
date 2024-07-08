<################################################################################
## Copyright(c) 2024 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:RemoveS3Objects.ps1
## @summary:Remove S3 Objects
##
## @since:2024/05/16
## @version:1.0
## @see:
## @parameter
##  1:�o�P�b�g��
##  2:KeyPrefix
##  3:�ێ�����
##  4:���[�W������
##  5:�C�x���g���O�o��
##  6:�W���o��
##
## @return:0:Success 9:�G���[�I�� / 99:Exception
################################################################################>

##########################
## �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$true)][string]$BucketName,
  [parameter(mandatory=$true)][string]$KeyPrefix,
  [parameter(mandatory=$true)][int]$Term,
  [string]$RegionName,
  [switch]$Eventlog=$false,
  [switch]$Stdout=$false
)

##########################
## ���W���[���̃��[�h
##########################
. .\LogController.ps1
. .\AWSLogonFunction.ps1

##########################
# �Œ�l 
##########################
[string]$CredenticialFile = "AWSCredential_Secure.xml"
[bool]$ErrorFlg = $false
[int]$SaveDays = 7
$ErrorActionPreference = "Stop"

##########################
## �x���̕\���}�~
##########################
## Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

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
if($Term -le 0) {
  $Log.Info("�ێ�������1�ȏ��ݒ肵�Ă��������B")
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
  if(-not $RegionName) {
   $RegionName = Get-DefaultAWSRegion
  }
  $Log.Info("AWS Region: $RegionName")

  $S3Bucket = Get-S3Bucket -BucketName $BucketName -Region $RegionName
  if ($S3Bucket) {
##    $Log.Info("Get-S3Object -BucketName $($S3Bucket.BucketName) -KeyPrefix $KeyPrefix `| Where-Object {`$`_.LastModified -lt ((get-Date).AddDays(-1 * $Term)).ToString(""yyyy/MM/dd hh:mm:ss"") -and `$`_.Key.LastIndexOf(""/"") -ne `$(`$`_.Key.Length -1)}")
    $S3Objects = Get-S3Object -BucketName $S3Bucket.BucketName -KeyPrefix $KeyPrefix | Where-Object {$_.LastModified -lt ((get-Date).AddDays(-1 * $Term)).ToString("yyyy/MM/dd hh:mm:ss") -and $_.Key.LastIndexOf("/") -ne $($_.Key.Length -1)}
    foreach ($Obj in $S3Objects) {
      $Log.Info("$($Obj.Key) ���폜���܂��B")
      Remove-S3Object -BucketName $BucketName -Key $Obj.Key -Force
    } 
    $Log.Info("�폜�������������܂����B")
  } else {
    $Log.Error("S3�o�P�b�g�����݂��܂���B")
    exit 1
  }
} catch {
  $this.Log.Error("�������ɃG���[���������܂����B")
  $this.Log.Error($_.Exception)
  exit 1
}
exit 0
