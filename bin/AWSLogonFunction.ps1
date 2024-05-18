<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:AWSLogonFunction.ps1
## @summary:AWS Logon 
##
## @since:2024/05/01
## @version:1.2
## @see:
## @parameter
##  1:AWS Login�F�؃t�@�C���p�X
##
## @return:$true:Success $false:Error 
################################################################################>

Import-Module .\LogController.ps1

Class AWSLogonFunction {
  
  [string]$ConfigPath
  [string]$ConfigPathSecureString
  [object]$ConfigInfo
  [object]$Log

  AWSLogonFunction([string] $ConfigPath) {
    $this.ConfigPath = $ConfigPath
  }

  AWSLogonFunction([string] $FullPath, [string] $FileName) {
    $this.ConfigPath = $FullPath + "/" + $FileName
  }

  [bool] Initialize() {
    $LogFilePath = Convert-Path . | Split-Path -Parent | Join-Path -ChildPath log -Resolve
    $LogFile = "AWSLogonFunction.log"
    $this.Log = New-Object LogController($($LogFilePath + "\" + $LogFile), $true)
    if($this.Initialize($this.Log)) {return $true} else {return $false}
  }

  [bool] Initialize([object] $Log) {
    try {
      $this.Log = $Log
      ##########################
      # �F�؏��擾
      ##########################
      if (($this.ConfigPath) -and (-not $(Test-Path $this.ConfigPath))) {
        $this.log.error("�F�؏��t�@�C�������݂��܂���B")
        return $false
      } else {
        $this.Log.Info("�F�؏��t�@�C���p�X�F" + (Split-Path $this.ConfigPath -Parent))
        $this.Log.Info("�F�؏��t�@�C�����F" + (Get-ChildItem $this.ConfigPath).Name)
        if ($(Test-Path $this.ConfigPath)) { $this.ConfigInfo = [xml](Get-Content $this.ConfigPath) }
        if(-not $this.ConfigInfo) { 
          $this.log.error("����̃t�@�C������F�؏�񂪓ǂݍ��߂܂���ł����B")
          return $false
        } 
      }
      return $true
    } catch {
      $this.Log.Error("�������ɃG���[���������܂����B")
      $this.Log.Error($("" + $Error[0] | Format-List --DisplayError))
      return $false
    }
  }

  [bool] Logon() {
    try {
      if (-not $this.Log) { if (-not $this.Initialize()) {return $false} }
      if ($this.ConfigInfo) {
        switch ($this.ConfigInfo.Configuration.AuthenticationMethod) {
          "IAMUser" {
            ##########################
            # AWS�ւ̃��O�C��(IAMUser)
            ##########################
            # Invoke Set-AWSCredential first
            $this.Log.Info("Invoke Set-AWSCredential -ProfileName $($this.ConfigInfo.Configuration.ProfileName)")
            $Credential = Get-AWSCredential -ListProfileDetail | Where-Object { $_.ProfileName -eq $this.ConfigInfo.Configuration.ProfileName} 
            $this.Log.Info("Profile Name: $($Credential.ProfileName)")
            Set-AWSCredential -ProfileName $Credential.ProfileName
            $Region = Get-DefaultAWSRegion
            $this.Log.Info("Default Region: $Region")
          }

          default {
            $this.Log.error("AWS�փ��O�C��:���s:�F�ؕ����ݒ�s��")
            return $false 
          }
        }
      }
      return $true
    } catch {
      $this.Log.Error("�������ɃG���[���������܂����B")
      $this.Log.Error($_.Exception)
      return $false
    }
    return $true
  }

  [bool] SetAWSCredential([string] $NewCredFileName) {
    try {
      if (-not $this.Log) { if (-not $this.Initialize()) {return $false} }
      $this.Log.Info("Set-AWSCredential -AccessKey $($this.ConfigInfo.Configuration.AccessKey) -SecretKey $($this.ConfigInfo.Configuration.SecretKey) -StoreAs $($this.ConfigInfo.Configuration.StoreAs)")
      $this.Log.Info("Get-AWSCredential -ProfileName $($this.ConfigInfo.Configuration.StoreAs)")
##      $this.Log.Info("Initialize-AWSDefaultConfiguration -ProfileName $($this.ConfigInfo.Configuration.StoreAs) -Region $($this.ConfigInfo.Configuration.Region)")
      $Credential = Get-AWSCredential -ProfileName $this.ConfigInfo.Configuration.StoreAs
      if (-not $Credential) {
        Set-AWSCredential -AccessKey $this.ConfigInfo.Configuration.AccessKey -SecretKey $this.ConfigInfo.Configuration.SecretKey -StoreAs $this.ConfigInfo.Configuration.StoreAs
        $this.Log.Info("$($this.ConfigInfo.Configuration.StoreAs)��o�^���܂����B")
      } else {
        $this.Log.Info("$($this.ConfigInfo.Configuration.StoreAs)�͓o�^�ς݂ł��B")
      } 
##      Initialize-AWSDefaultConfiguration -ProfileName $this.ConfigInfo.Configuration.StoreAs -Region $this.ConfigInfo.Configuration.Region
      Set-DefaultAWSRegion -Region $this.ConfigInfo.Configuration.Region
      $this.Log.Info("$($this.ConfigInfo.Configuration.region)��ݒ肵�܂����B")
      
      $Credential = Get-AWSCredential -ListProfileDetail | Where-Object { $_.ProfileName -eq $this.ConfigInfo.Configuration.StoreAs} 
      $this.Log.Info("Profile Name: $($Credential.ProfileName)")
      $Region = Get-DefaultAWSRegion
      $this.Log.Info("Default Region: $Region")

      $newElt = $this.ConfigInfo.CreateElement('ProfileName')
      $newText = $this.ConfigInfo.CreateTextNode($this.ConfigInfo.Configuration.StoreAs)
      $newElt.AppendChild($newText) | Out-Null
      $this.ConfigInfo.LastChild.AppendChild($newElt)
      $child_node = $this.ConfigInfo.SelectSingleNode('//AccessKey')
      $this.ConfigInfo.Configuration.RemoveChild($child_node) | Out-Null
      $child_node = $this.ConfigInfo.SelectSingleNode('//SecretKey')
      $this.ConfigInfo.Configuration.RemoveChild($child_node) | Out-Null
      $child_node = $this.ConfigInfo.SelectSingleNode('//StoreAs')
      $this.ConfigInfo.Configuration.RemoveChild($child_node) | Out-Null
      $this.ConfigPathSecureString = $(Split-Path $this.ConfigPath -Parent) + "\" + $NewCredFileName
      $this.ConfigInfo.Save($this.ConfigPathSecureString)
      $this.Log.Info("�F�؏��t�@�C���p�X�F" + (Split-Path $this.ConfigPathSecureString -Parent))
      $this.Log.Info("�F�؏��t�@�C�����F" + (Get-ChildItem $this.ConfigPathSecureString).Name)
      return $true
    } catch {
      $this.Log.Error("�������ɃG���[���������܂����B")
      $this.Log.Error($_.Exception)
      return $false
    }
  }
}
