<################################################################################
## Copyright(c) 2025 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:SQLMetadataMaint.ps1
## @summary:SSM CreateVssSnapshot���^�f�[�^�����e�i���X
##
## @since:2025/02/16
## @version:1.0
## @see:
## @parameter
##  1:����
##
## @return:0:Success 
################################################################################>

##########################################################
# �p�����[�^�ݒ�
##########################################################
param (
  [parameter(mandatory=$true)][int]$Generation
)

##########################################################
# �A�b�v���[�h��ݒ�
##########################################################
$SharedFolder = "\\172.31.39.174\Metadata"
$UploadDir = Get-Date -Format "yyyyMMdd"
$SourceFolder = "C:\ProgramData\Amazon\AwsVss\VssMetadata"
$UploadUser = ".\Administrator"
$UploadPass = 'A9NH$jU6hg!SZ6WV2;9idyqk*KIal0;C'

try {
  ##########################################################
  # �s�v���^�f�[�^�t�@�C���폜
  ##########################################################
  $SQLMetadataList = $(Get-Childitem C:\ProgramData\Amazon\AwsVss\VssMetadata\*SqlServerWriter.xml)| Sort-Object LastWriteTime -Descending | Select-Object FullName, Name
  $BCDMetadataList = $(Get-Childitem C:\ProgramData\Amazon\AwsVss\VssMetadata\*BCD.xml)| Sort-Object LastWriteTime -Descending | Select-Object FullName, Name

  foreach($SQLMetadataFile in $SQLMetadataList) { Write-Output "SqlServerWriter: $($SQLMetadataFile.Name)" }
  foreach($BCDMetadataFile in $BCDMetadataList) { Write-Output "BCD: $($BCDMetadataFile.Name)" }

  for($cnt = $Generation; $cnt -lt $SQLMetadataList.Count; $cnt++) {
    Write-Output "Delete Metadata File: $($SQLMetadataList[$cnt].Name)"
    Remove-Item $SQLMetadataList[$cnt].FullName -Force
  }

  for($cnt = $Generation; $cnt -lt $BCDMetadataList.Count; $cnt++) {
    Write-Output "Delete Metadata File: $($BCDMetadataList[$cnt].Name)"
    Remove-Item $BCDMetadataList[$cnt].FullName -Force
  }

  ##########################################################
  # �A�b�v���[�h�p�̃Q�X�g�F��Credential�𐶐�����
  ##########################################################
  $StrSec = ConvertTo-SecureString $UploadPass -AsPlainText -Force
  $Cred = New-Object System.Management.Automation.PsCredential($UploadUser, $StrSec)

  ##########################################################
  # PS�h���C�u�Ƀ}�E���g����
  ##########################################################
  $psDriveName = "Z"
  $psDriveInfo = Get-PSDrive | Where-Object {$_.Name -eq $psDriveName}
  if ($nul -ne $psDriveInfo) {
     Remove-PSDrive -Name $psDriveName
  }
  New-PSDrive -Name $psDriveName -PSProvider FileSystem -Root $SharedFolder -Credential $Cred

  ##########################################################
  # �A�b�v���[�h����
  ##########################################################
  $UploadUri = Join-Path $SharedFolder $UploadDir
  Robocopy $SourceFolder $UploadUri /DCOPY:DA /COPY:DAT /R:5 /W:30
  $result = $LASTEXITCODE
  Write-Output "Robocopy Result Code: $result"
  if (8 -le $result) {
    Write-Output "robocopy �ŃG���[���������܂����B"
    $ErrorFlg = 1
  }

  ##########################################################
  # ����Ǘ�
  ##########################################################
  $TargetDir = Get-ChildItem $sharedFolder -Recurse | Where-Object {($_.Mode -eq "d-----")} | Sort-Object CreationTime -Descending
  for($cnt = $Generation; $cnt -lt $TargetDir.Count; $cnt++) {
    Write-Output "Delete Backup Metadata File: $($TargetDir[$cnt].FullName)"
    Remove-Item $TargetDir[$cnt].FullName -Recurse -Force
  }

  ##########################################################
  # PS�h���C�u���A���}�E���g����
  ##########################################################
  Remove-PSDrive -Name $psDriveName -Force

  #################################################
  # �G���[�n���h�����O
  #################################################
  if($ErrorFlg) {
    Write-Error("SQL Server Metadata Maintanance Job Error")
    exit 9
  } else {
    Write-Output("SQL Server Metadata Maintanance Job Completed")
    exit 0
  }
} catch {
    Write-Error("SQL Server Metadata Maintanance Job Excute Error")
    Write-Error($_.Exception)
    exit 99
}
exit 0