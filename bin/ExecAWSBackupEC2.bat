::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Copyright(c) 2024 BeeX Inc. All rights reserved.
:: @auther:Naruhiro Ikeya
::
:: @name:ExecAWSBackupJob.bat
:: @summary:ExecAWSBackupJob.ps1 Wrapper
::
:: @since:20i24/05/23
:: @version:1.0
:: @see:
:: @parameter
::  1:AWSVM名
::  2:Vault名
::  3:バックアップ保管日数
::  4:AWS Backup バックアップウインドウ(開始)
::  5:AWS Backup バックアップウインドウ(完了)
::
:: @return:0:Success 1:パラメータエラー 99:異常終了
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

:::::::::::::::::::::::::::::
::      環境変数設定       ::
:::::::::::::::::::::::::::::
SET __LOG_CYCLE__=7
SET __EXPIRE_DAYS__=7

:::::::::::::::::::::::::::::::::::
::      パラメータチェック       ::
:::::::::::::::::::::::::::::::::::
SET __ARGC__=0
FOR %%a IN ( %* ) DO SET /A __ARGC__+=1

IF %__ARGC__% neq 5 (
  SET __TIME__=%TIME:~0,8%
  SET __TIME__=!__TIME__: =0!
  ECHO [%DATE% !__TIME__!] Usage:%~nx0 EC2名 vault名 バックアップ保持日数 BackupWindow[Start] BackupWindow[End]
  EXIT /B 1
) 

SET __VMNAME__=%1
SET __VAULTNAME__=%2
SET /A __CYCLEDAYS__=%3
SET /A __START_WINDOW__=%4
SET /A __COMPLETE_WINDOW__=%5

::::::::::::::::::::::::::::::::::
::      タイムスタンプ生成      ::
::::::::::::::::::::::::::::::::::
SET __TODAY__=%DATE:/=%
SET __TIME__=%TIME::=%
SET __TIME__=%__TIME__:.=%
SET __NOW__=%__TODAY__%%__TIME__: =0%

::::::::::::::::::::::::::::::::::::
::      出力ログファイル生成      ::
::::::::::::::::::::::::::::::::::::
FOR /F "usebackq" %%L IN (`powershell -command "Split-Path %~dp0 -Parent | Join-Path -ChildPath log"`) DO SET __LOGPATH__=%%L
IF NOT EXIST %__LOGPATH__% MKDIR %__LOGPATH__%
SET __LOGFILE__=%__LOGPATH__%\%~n0_%__VMNAME__%_%__NOW__%.log

::::::::::::::::::::::::::::::::::::::::::::::
::      出力ログファイルローテーション      ::
::::::::::::::::::::::::::::::::::::::::::::::
FORFILES /P %__LOGPATH__% /M *.log /D -%__LOG_CYCLE__% /C "CMD /C IF @isdir==FALSE DEL /Q @path" > NUL 2>&1

::::::::::::::::::::::::::::::::::::::
::      スクリプト本体存在確認      ::
::::::::::::::::::::::::::::::::::::::
IF NOT EXIST %~dpn0.ps1 (
  CALL :__ECHO__ AWS Backup実行スクリプト（%~n0.ps1）が存在しません。
  EXIT /B %__ERROR_CODE__%
)

CD /d %~dp0

::::::::::::::::::::::::::::::::::
::      スクリプト本体実行      ::
::::::::::::::::::::::::::::::::::
CALL :__ECHO__ AWS Backup実行処理（%~n0.ps1）を開始します。
if "%PROCESSOR_ARCHITECTURE%" EQU "x86" (
    set EXEC_POWERSHELL="C:\Windows\sysnative\WindowsPowerShell\v1.0\powershell.exe"
)
if "%PROCESSOR_ARCHITECTURE%" EQU "AMD64" (
    set EXEC_POWERSHELL="C:\Windows\system32\WindowsPowerShell\v1.0\powershell.exe"
)

%EXEC_POWERSHELL% -ExecutionPolicy RemoteSigned -NoProfile -inputformat none -command "%~dpn0.ps1 -Stdout -Windows %__VMNAME__% %__VAULTNAME__% %__CYCLEDAYS__% %__START_WINDOW__% %__COMPLETE_WINDOW__%;exit $LASTEXITCODE" >>"%__LOGFILE__%"

::::::::::::::::::::::::::::::::::::::::::
::      スクリプト本体実行結果確認      ::
::::::::::::::::::::::::::::::::::::::::::
IF ERRORLEVEL 9 (
  CALL :__ECHO__ AWS Backup実行処理中にエラーが発生しました。
  EXIT /B %__ERROR_CODE__%
)
IF ERRORLEVEL 2 (
  CALL :__ECHO__ AWS Backup実行処理（Take Snapshotフェーズ）が完了しました。
  EXIT /B 0
)
IF ERRORLEVEL 1 (
  CALL :__ECHO__ AWS Bakup実行処理中にパラメータエラーが発生しました。
  EXIT /B %__ERROR_CODE__%
)
CALL :__ECHO__ AWS Backup実行処理が完了しました。

:__QUIT__
EXIT /B 0

:__ECHO__
SET __TIME__=%TIME:~0,8%
ECHO [%DATE% %__TIME__: =0%] %*
ECHO [%DATE% %__TIME__: =0%] %* >>"%__LOGFILE__%"
EXIT /B 0
