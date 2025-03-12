###############################
# メタデータ表示
###############################
$SQLMetadataList = $(Get-Childitem C:\ProgramData\Amazon\AwsVss\VssMetadata\*SqlServerWriter.xml)| Sort-Object LastWriteTime -Descending | Select-Object FullName, Name, LastWriteTime
foreach($SQLMetadata in $SQLMetadataList) {
  $SnapshotSetId = [regex]::Matches($SQLMetadata.Name, '{.*}')
  echo $('SnapshotID(' + $($SQLMetadata.LastWriteTime) + '):' + $($SnapshotSetId.Value.Substring(1,$($SnapshotSetId.Length) -2)))
}

###############################
# C:\ProgramData\Amazon\Tools\ebsnvme-id.exe
# コマンド実行
###############################
$EBSNVMECMD=C:\ProgramData\Amazon\Tools\ebsnvme-id.exe
$VolumeInfo = $EBSNVMECMD
$colDiskInfo = New-Object System.Collections.ArrayList
for($cnt=0; $cnt -lt $VolumeInfo.Count; $cnt+=4) {
  $objDiskInfo = New-Object PSObject
  $objDiskInfo | Add-Member -MemberType NoteProperty -Name "DiskNumber" -Value $($($VolumeInfo[$cnt]) -split ":\s*")[1]
  $objDiskInfo | Add-Member -MemberType NoteProperty -Name "VolumeID" -Value $($($VolumeInfo[$cnt+1]) -split ":\s*")[1]
  $objDiskInfo | Add-Member -MemberType NoteProperty -Name "DeviceName" -Value $($($VolumeInfo[$cnt+2]) -split ":\s*")[1]
  $colDiskInfo.add($objDiskInfo) | Out-Null
}

###############################
# オフラインボリュームの表示
###############################
$arrDeviceMapping = New-Object System.Collections.Generic.List[string]
$RemovedDriveLetterDisks = Get-Partition | Select-Object DriveLetter, DiskNumber, UniqueId | Where-Object {$_.Driveletter -eq 0}
foreach($DiskInfo in $RemovedDriveLetterDisks) {
  $TargetDisk = $colDiskInfo | Where-Object { $_.DiskNumber -eq $DiskInfo.DiskNumber } 
  $arrDeviceMapping.Add($TargetDisk.VolumeID + ':' + $TargetDisk.DeviceName)
}
echo VolumeIdDeviceNamePairs:$($arrDeviceMapping -Join ";")