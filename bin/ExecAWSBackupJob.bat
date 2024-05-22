::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Copyright(c) 2020 BeeX Inc. All rights reserved.
:: @auther:Naruhiro Ikeya
::
:: @name:ExecAzureBackupJob.bat
:: @summary:ExecAzureBackupJob.ps1 Wrapper
::
:: @since:2019/01/28
:: @version:1.0
:: @see:
:: @parameter
::  1:AzureVM名
::  2:Recovery Serviceコンテナー名
::  3:Azure Backupジョブポーリング間隔（秒）
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

IF %__ARGC__% neq 4 (
  SET __TIME__=%TIME:~0,8%
  SET __TIME__=!__TIME__: =0!
  ECHO [%DATE% !__TIME__!] Usage:%~nx0 AzureVM名 RecoveryServiceコンテナー名 バックアップ保持日数 Backupジョブポーリング間隔 
  EXIT /B 1
) 

SET __VMNAME__=%1
SET __R_S_CONTAINER__=%2
SET /A __ADD_DAYS__=%3
SET /A __JOB_TIMEOUT__=%4

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
SET __LOGFILE__=%__LOGPATH__%\%~n0_%_VMNAME__%_%__NOW__%.log

::::::::::::::::::::::::::::::::::::::::::::::
::      出力ログファイルローテーション      ::
::::::::::::::::::::::::::::::::::::::::::::::
FORFILES /P %__LOGPATH__% /M *.log /D -%__LOG_CYCLE__% /C "CMD /C IF @isdir==FALSE DEL /Q @path" > NUL 2>&1

::::::::::::::::::::::::::::::::::::::
::      スクリプト本体存在確認      ::
::::::::::::::::::::::::::::::::::::::
IF NOT EXIST %~dpn0.ps1 (
  CALL :__ECHO__ Azure Backup実行スクリプト（%~n0.ps1）が存在しません。
  EXIT /B %__ERROR_CODE__%
)

CD /d %~dp0

::::::::::::::::::::::::::::::::::
::      スクリプト本体実行      ::
::::::::::::::::::::::::::::::::::
CALL :__ECHO__ Azure Backup実行処理（%~n0.ps1）を開始します。
if "%PROCESSOR_ARCHITECTURE%" EQU "x86" (
    set EXEC_POWERSHELL="C:\Windows\sysnative\WindowsPowerShell\v1.0\powershell.exe"
)
if "%PROCESSOR_ARCHITECTURE%" EQU "AMD64" (
    set EXEC_POWERSHELL="C:\Windows\system32\WindowsPowerShell\v1.0\powershell.exe"
)

%EXEC_POWERSHELL% -ExecutionPolicy RemoteSigned -NoProfile -inputformat none -command "%~dpn0.ps1 -Stdout %__VMNAME__% %__R_S_CONTAINER__% %__ADD_DAYS__% %__JOB_TIMEOUT__%;exit $LASTEXITCODE" >>"%__LOGFILE__%"

::::::::::::::::::::::::::::::::::::::::::
::      スクリプト本体実行結果確認      ::
::::::::::::::::::::::::::::::::::::::::::
IF ERRORLEVEL 9 (
  CALL :__ECHO__ Azure Backup実行処理中にエラーが発生しました。
  EXIT /B %__ERROR_CODE__%
)
IF ERRORLEVEL 2 (
  CALL :__ECHO__ Azure Backup実行処理（Take Snapshotフェーズ）が完了しました。
  EXIT /B 0
)
IF ERRORLEVEL 1 (
  CALL :__ECHO__ Azure Bakup実行処理中にパラメータエラーが発生しました。
  EXIT /B %__ERROR_CODE__%
)
CALL :__ECHO__ Azure Backup実行処理が完了しました。

:__QUIT__
EXIT /B 0

:__ECHO__
SET __TIME__=%TIME:~0,8%
ECHO [%DATE% %__TIME__: =0%] %*
ECHO [%DATE% %__TIME__: =0%] %* >>"%__LOGFILE__%"
EXIT /B 0
