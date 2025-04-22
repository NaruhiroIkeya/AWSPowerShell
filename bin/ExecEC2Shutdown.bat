::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Copyright(c) 2024 BeeX Inc. All rights reserved.
:: @auther:Naruhiro Ikeya
::
:: @name:ExecEC2Shutdown.bat
:: @summary:EC2ShutdownController.ps1 Wrapper
::
:: @since:2024/05/20
:: @version:1.0
:: @see:
:: @parameter
::  1:EC2名
::  2:Region名
::
:: @return:0:Success 1:Error
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

:::::::::::::::::::::::::::::
::      環境変数設定       ::
:::::::::::::::::::::::::::::
SET __LOG_CYCLE__=7
SET __APL_PS1__=EC2BootController.ps1
SET __EXPIRE_DAYS__=7
SET __ERROR_CODE__=-1

:::::::::::::::::::::::::::::::::::
::      パラメータチェック       ::
:::::::::::::::::::::::::::::::::::
SET __ARGC__=0
FOR %%a IN ( %* ) DO SET /A __ARGC__+=1

IF %__ARGC__% lss 1 (
  SET __TIME__=%TIME:~0,8%
  SET __TIME__=!__TIME__: =0!
  ECHO [%DATE% !__TIME__!] Usage:%~n0 EC2名 [Region名]
  EXIT /B %__ERROR_CODE__%
) 

SET __EC2NAME__=%1
SET __REGIONNAME__=%2

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
SET __LOGFILE__=%__LOGPATH__%\%~n0_%__EC2NAME__%_%__NOW__%.log

::::::::::::::::::::::::::::::::::::::::::::::
::      出力ログファイルローテーション      ::
::::::::::::::::::::::::::::::::::::::::::::::
FORFILES /P %__LOGPATH__% /M *.log /D -%__LOG_CYCLE__% /C "CMD /C IF @isdir==FALSE DEL /Q @path" > NUL 2>&1

::::::::::::::::::::::::::::::::::::::
::      スクリプト本体存在確認      ::
::::::::::::::::::::::::::::::::::::::
SET __PS_SCRIPT__=%~dp0%__APL_PS1__%
IF NOT EXIST %__PS_SCRIPT__% (
  CALL :__ECHO__ EC2停止スクリプトが存在しません。
  EXIT /B %__ERROR_CODE__%
)

CD /d %~dp0

::::::::::::::::::::::::::::::::::
::      スクリプト本体実行      ::
::::::::::::::::::::::::::::::::::
CALL :__ECHO__ 仮想マシン停止処理（%__PS_SCRIPT__%）を開始します。
IF "%PROCESSOR_ARCHITECTURE%" EQU "x86" (
    SET EXEC_POWERSHELL="C:\Windows\sysnative\WindowsPowerShell\v1.0\powershell.exe"
)
IF "%PROCESSOR_ARCHITECTURE%" EQU "AMD64" (
    SET EXEC_POWERSHELL="C:\Windows\system32\WindowsPowerShell\v1.0\powershell.exe"
)

IF "%__REGIONNAME__%" EQU "" (
  %EXEC_POWERSHELL% -NoProfile -inputformat none -command "%__PS_SCRIPT__% -Shutdown -Stdout -EC2Name %__EC2NAME__%;exit $LASTEXITCODE" >>"%__LOGFILE__%"
) ELSE (
  %EXEC_POWERSHELL% -NoProfile -inputformat none -command "%__PS_SCRIPT__% -Shutdown -Stdout -RegionName %__REGIONNAME__% -EC2Name %__EC2NAME__%;exit $LASTEXITCODE" >>"%__LOGFILE__%"
)
::::::::::::::::::::::::::::::::::::::::::
::      スクリプト本体実行結果確認      ::
::::::::::::::::::::::::::::::::::::::::::
IF ERRORLEVEL 1 (
  CALL :__ECHO__ EC2停止処理中にエラーが発生しました。
  EXIT /B %__ERROR_CODE__%
)
CALL :__ECHO__ EC2停止処理が完了しました。

:__QUIT__
EXIT /B 0

:__ECHO__
SET __TIME__=%TIME:~0,8%
ECHO [%DATE% %__TIME__: =0%] %*
ECHO [%DATE% %__TIME__: =0%] %* >>"%__LOGFILE__%"
EXIT /B 0
