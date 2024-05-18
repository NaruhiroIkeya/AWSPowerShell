<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:LogController.ps1
## @summary:Log Controller
##
## @since:2019/06/12
## @version:1.0
## @see:
## @parameter
##  1:Stdout：標準出力
##  2:EventLog：イベントログ出力
##  3:FullPath：ファイル出力パス
##
## @return:
################################################################################>

Class LogController {
  [bool] $StdOut
  [bool] $EventLog
  [int] $EventID = 6338
  [String] $EventSource
  [String] $FullPath
  [String] $LogBaseName
  [bool] $Generation
  [string]$LogDir
  [hashtable] $Saverity = @{info = 1; warn = 2; err = 3}
  [hashtable] $EventType = @{1 = "Information"; 2 = "Warning"; 3 = "Error"}
  [hashtable] $LogType = @{1 = "INFO"; 2 = "WARN"; 3 = "ERROR"}

  #####################################
  # 標準出力のみ
  #####################################
  LogController() {
    $this.EventLog = $false
    $this.StdOut = $true
  }

  #####################################
  # 標準出力 + イベントログ
  #####################################
  LogController([bool] $EventLog, [string] $EventSource) {
    $this.EventLog = $EventLog
    $this.EventSource = $EventSource
    $this.StdOut = $true

    #####################################
    # EventLog書き込み用ソース情報登録
    #####################################
    if($EventLog -and (-not $EventSource)) { $this.EventSource=$(Get-ChildItem $MyInvocation.MyCommand.Path).Name } 
    if($EventLog -and $EventSource) {
      if ([System.Diagnostics.EventLog]::SourceExists($EventSource) -eq $false) {
          [System.Diagnostics.EventLog]::CreateEventSource($EventSource, "Application")
      }
    }
  }

  #####################################
  # 標準出力 + ファイル出力
  #####################################
  LogController([String] $FullPath, [bool]$Generation) {
    $this.FullPath = $FullPath
    $this.Generation = $Generation
    $this.StdOut = $true

    $this.InitializeLog()
  }

  #####################################
  # 標準出力 / ファイル出力 / イベントログ
  #####################################
  LogController([String] $FullPath, [bool]$Generation, [bool] $EventLog, [string] $EventSource, $StdOut) {
    $this.FullPath = $FullPath
    $this.Generation = $Generation
    $this.EventLog = $EventLog
    $this.EventSource = $EventSource
    $this.StdOut = $StdOut

    #####################################
    # EventLog書き込み用ソース情報登録
    #####################################
    if($EventLog -and (-not $EventSource)) { $this.EventSource=$(Get-ChildItem $MyInvocation.MyCommand.Path).Name } 
    if($EventLog -and $EventSource) {
      if ([System.Diagnostics.EventLog]::SourceExists($EventSource) -eq $false) {
          [System.Diagnostics.EventLog]::CreateEventSource($EventSource, "Application")
      }
    }

    $this.InitializeLog()
  }
   
  [void] info([string] $Message) {
    $this.Log($Message, $this.Saverity.info)
  }

  [void] warn([string] $Message) {
    $this.Log($Message, $this.Saverity.warn)
  }

  [void] error([string] $Message) {
    $this.Log($Message, $this.Saverity.err)
  }

  hidden [void] Log([string]$Message, [int]$Saverity) {
    #if($this.StdOut) { [Console]::WriteLine("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] $Message") }
    if($this.StdOut) { Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $this.LogType[$Saverity]  + " " + $Message) | Out-Host }
    if($this.EventLog) { Write-EventLog -LogName Application -EntryType $this.EventType[$Saverity] -S $this.EventSource -EventId $this.EventID -Message $Message }
    if($null -ne $this.FullPath) {
      # ログ出力
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $this.LogType[$Saverity]  + " " + $Message) | Out-File -FilePath $this.FullPath -Encoding Default -append
    }
  }

  #####################################
  # ログファイル初期化
  #####################################
  hidden [void] InitializeLog() {
    #####################################
    # ログフォルダーが存在しなかったら作成
    #####################################
    $this.LogDir = Split-Path $this.FullPath -Parent
    if(-not (Test-Path($this.LogDir))) {
      New-Item $this.LogDir -Type Directory
    }
    #####################################
    # タイムスタンプ形式のログファイル作成 
    #####################################
    if(-not $this.Generation) {
      $this.LogBaseName = [System.IO.Path]::GetFileNameWithoutExtension($this.FullPath)
      $this.FullPath = $($this.LogDir + "\" + [System.IO.Path]::GetFileNameWithoutExtension($this.FullPath) + "_" + (Get-Date -UFormat "%Y%m%d%H%M") + [System.IO.Path]::GetExtension($this.FullPath))
    }
  }

  #####################################
  # ログローテーション
  #####################################
  [void] RotateLog([int]$Generation) {
    $this.info("ログローテーション処理を開始します。")
    if(-not $this.Generation) { exit }
    foreach($cntr in ($Generation)..1) {
      if($cntr -ne 1) {
        $SourceFile = $($this.LogDir + "\" + (Get-ChildItem $this.FullPath).BaseName + "_" + $($cntr - 1) + (Get-ChildItem $this.FullPath).Extension)
        $TargetFile = $($this.LogDir + "\" + (Get-ChildItem $this.FullPath).BaseName + "_" + $($cntr) + (Get-ChildItem $this.FullPath).Extension)
      } else {
        $SourceFile = $($this.LogDir + "\" + (Get-ChildItem $this.FullPath).BaseName + (Get-ChildItem $this.FullPath).Extension)
        $TargetFile = $($this.LogDir + "\" + (Get-ChildItem $this.FullPath).BaseName + "_" + $($cntr) + (Get-ChildItem $this.FullPath).Extension)
      }
      if((Test-Path($TargetFile)) -and ($cntr -eq $Generation)) {
        Remove-Item $TargetFile -Force
        Move-Item $SourceFile $TargetFile
        Continue
      } elseif((Test-Path($SourceFile)) -and (-not (Test-Path($TargetFile)))) {
        Move-Item $SourceFile $TargetFile
      }
    }
    $this.info("ログローテーション処理が完了しました。")
  }

  #####################################
  # 過去ログ削除
  #####################################
  [void] DeleteLog([int] $Days) {
    $this.info("ログ削除処理を開始します。")
    Get-ChildItem -Path $this.LogDir | Where-Object {($_.Name -like "$($this.LogBaseName)*") -and ($_.Mode -eq "-a----") -and ($_.CreationTime -lt (Get-Date).AddDays(-1 * $Days))} | Remove-Item -Recurse -Force
    $this.info("ログ削除処理が完了しました。")
  }

  #####################################
  # ログファイル名取得
  #####################################
  [string] getLogInfo(){ return $this.FullPath }
}