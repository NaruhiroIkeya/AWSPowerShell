::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Copyright(c) 2024 BeeX Inc. All rights reserved.
:: @auther:Naruhiro Ikeya
::
:: @name:RemoveObjectsS3.bat
:: @summary:RemoveObjectsS3.ps1 Wrapper
::
:: @since:2024/08/13
:: @version:1.0
:: @see:
:: @parameter
::  1:バケット名
::  2:プレフィックス
::  3:マッチング文字列
::  4:サイクル期間
::
:: @return:0:Success 1:Error
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

:::::::::::::::::::::::::::::
::      環境変数設定       ::
:::::::::::::::::::::::::::::
SET __LOG_CYCLE__=7
SET __APL_PS1__=%~n0.ps1
SET __ERROR_CODE__=-1

:::::::::::::::::::::::::::::::::::
::      パラメータチェック       ::
:::::::::::::::::::::::::::::::::::
FOR /F "usebackq" %%L IN (`powershell -command "\"%*\".split(\" \").count"`) DO SET __ARGC__=%%L

IF %__ARGC__% lss 4 (
  SET __TIME__=%TIME:~0,8%
  SET __TIME__=!__TIME__: =0!
  ECHO [%DATE% !__TIME__!] Usage:%~n0 バケット名 プレフィックス 検索パターン 保持期間
  EXIT /B %__ERROR_CODE__%
) 

SET __BUCKETNAME__=%1
SET __PREFIX__=%2
SET __PATTERN__=%3
SET /A __CYCLE__=%4

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
SET __LOGFILE__=%__LOGPATH__%\%~n0_%__BUCKETNAME__%_%__NOW__%.log

::::::::::::::::::::::::::::::::::::::::::::::
::      出力ログファイルローテーション      ::
::::::::::::::::::::::::::::::::::::::::::::::
FORFILES /P %__LOGPATH__% /M *.log /D -%__LOG_CYCLE__% /C "CMD /C IF @isdir==FALSE DEL /Q @path" > NUL 2>&1

::::::::::::::::::::::::::::::::::::::
::      スクリプト本体存在確認      ::
::::::::::::::::::::::::::::::::::::::
SET __PS_SCRIPT__=%~dp0%__APL_PS1__%
IF NOT EXIST %__PS_SCRIPT__% (
  CALL :__ECHO__ S3オブジェクト削除スクリプトが存在しません。
  EXIT /B %__ERROR_CODE__%
)

CD /d %~dp0

::::::::::::::::::::::::::::::::::
::      スクリプト本体実行      ::
::::::::::::::::::::::::::::::::::
CALL :__ECHO__ 仮想マシン起動処理（%__PS_SCRIPT__%）を開始します。
if "%PROCESSOR_ARCHITECTURE%" EQU "x86" (
    set EXEC_POWERSHELL="C:\Windows\sysnative\WindowsPowerShell\v1.0\powershell.exe"
)
if "%PROCESSOR_ARCHITECTURE%" EQU "AMD64" (
    set EXEC_POWERSHELL="C:\Windows\system32\WindowsPowerShell\v1.0\powershell.exe"
)

ECHO %EXEC_POWERSHELL% -NoProfile -inputformat none -command "%__PS_SCRIPT__% -Stdout -BucketName %__BUCKETNAME__% -KeyPrefix %__PREFIX__% -KeyPattern %__PATTERN__% -Term %__CYCLE__%

%EXEC_POWERSHELL% -NoProfile -inputformat none -command "%__PS_SCRIPT__% -Stdout -BucketName %__BUCKETNAME__% -KeyPrefix %__PREFIX__% -KeyPattern %__PATTERN__% -Term %__CYCLE__%;exit $LASTEXITCODE" >>"%__LOGFILE__%"

::::::::::::::::::::::::::::::::::::::::::
::      スクリプト本体実行結果確認      ::
::::::::::::::::::::::::::::::::::::::::::
IF ERRORLEVEL 1 (
  CALL :__ECHO__ S3オブジェクト削除処理中にエラーが発生しました。
  EXIT /B %__ERROR_CODE__%
)
CALL :__ECHO__ S3オブジェクト削除処理が完了しました。

:__QUIT__
EXIT /B 0

:__ECHO__
SET __TIME__=%TIME:~0,8%
ECHO [%DATE% %__TIME__: =0%] %*
ECHO [%DATE% %__TIME__: =0%] %* >>"%__LOGFILE__%"
EXIT /B 0