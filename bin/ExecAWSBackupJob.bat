::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Copyright(c) 2024 BeeX Inc. All rights reserved.
:: @auther:Naruhiro Ikeya
::
:: @name:ExecAzureBackupJob.bat
:: @summary:ExecAzureBackupJob.ps1 Wrapper
::
:: @since:20i24/05/23
:: @version:1.0
:: @see:
:: @parameter
::  1:AWSVM��
::  2:Vault��
::  3:�o�b�N�A�b�v�ۊǓ���
::  4:AWS Backup �o�b�N�A�b�v�E�C���h�E
::  5:���^�[���X�e�[�^�X�i�X�i�b�v�V���b�g�҂��A�����҂��j
::
:: @return:0:Success 1:�p�����[�^�G���[ 99:�ُ�I��
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

:::::::::::::::::::::::::::::
::      ���ϐ��ݒ�       ::
:::::::::::::::::::::::::::::
SET __LOG_CYCLE__=7
SET __EXPIRE_DAYS__=7

:::::::::::::::::::::::::::::::::::
::      �p�����[�^�`�F�b�N       ::
:::::::::::::::::::::::::::::::::::
SET __ARGC__=0
FOR %%a IN ( %* ) DO SET /A __ARGC__+=1

IF %__ARGC__% neq 4 (
  SET __TIME__=%TIME:~0,8%
  SET __TIME__=!__TIME__: =0!
  ECHO [%DATE% !__TIME__!] Usage:%~nx0 EC2�� vault�� �o�b�N�A�b�v�ێ����� BackupWindow
  EXIT /B 1
) 

SET __VMNAME__=%1
SET __VAULTNAME__=%2
SET /A __CYCLEDAYS__=%3
SET /A __BACKUPWINDOW__=%4

::::::::::::::::::::::::::::::::::
::      �^�C���X�^���v����      ::
::::::::::::::::::::::::::::::::::
SET __TODAY__=%DATE:/=%
SET __TIME__=%TIME::=%
SET __TIME__=%__TIME__:.=%
SET __NOW__=%__TODAY__%%__TIME__: =0%

::::::::::::::::::::::::::::::::::::
::      �o�̓��O�t�@�C������      ::
::::::::::::::::::::::::::::::::::::
FOR /F "usebackq" %%L IN (`powershell -command "Split-Path %~dp0 -Parent | Join-Path -ChildPath log"`) DO SET __LOGPATH__=%%L
IF NOT EXIST %__LOGPATH__% MKDIR %__LOGPATH__%
SET __LOGFILE__=%__LOGPATH__%\%~n0_%_VMNAME__%_%__NOW__%.log

::::::::::::::::::::::::::::::::::::::::::::::
::      �o�̓��O�t�@�C�����[�e�[�V����      ::
::::::::::::::::::::::::::::::::::::::::::::::
FORFILES /P %__LOGPATH__% /M *.log /D -%__LOG_CYCLE__% /C "CMD /C IF @isdir==FALSE DEL /Q @path" > NUL 2>&1

::::::::::::::::::::::::::::::::::::::
::      �X�N���v�g�{�̑��݊m�F      ::
::::::::::::::::::::::::::::::::::::::
IF NOT EXIST %~dpn0.ps1 (
  CALL :__ECHO__ Azure Backup���s�X�N���v�g�i%~n0.ps1�j�����݂��܂���B
  EXIT /B %__ERROR_CODE__%
)

CD /d %~dp0

::::::::::::::::::::::::::::::::::
::      �X�N���v�g�{�̎��s      ::
::::::::::::::::::::::::::::::::::
CALL :__ECHO__ Azure Backup���s�����i%~n0.ps1�j���J�n���܂��B
if "%PROCESSOR_ARCHITECTURE%" EQU "x86" (
    set EXEC_POWERSHELL="C:\Windows\sysnative\WindowsPowerShell\v1.0\powershell.exe"
)
if "%PROCESSOR_ARCHITECTURE%" EQU "AMD64" (
    set EXEC_POWERSHELL="C:\Windows\system32\WindowsPowerShell\v1.0\powershell.exe"
)

%EXEC_POWERSHELL% -ExecutionPolicy RemoteSigned -NoProfile -inputformat none -command "%~dpn0.ps1 -Stdout %__VMNAME__% %__VAULTNAME__% %__CYCLEDAYS__% %__BACKUPWINDOW__%;exit $LASTEXITCODE" >>"%__LOGFILE__%"

::::::::::::::::::::::::::::::::::::::::::
::      �X�N���v�g�{�̎��s���ʊm�F      ::
::::::::::::::::::::::::::::::::::::::::::
IF ERRORLEVEL 9 (
  CALL :__ECHO__ Azure Backup���s�������ɃG���[���������܂����B
  EXIT /B %__ERROR_CODE__%
)
IF ERRORLEVEL 2 (
  CALL :__ECHO__ Azure Backup���s�����iTake Snapshot�t�F�[�Y�j���������܂����B
  EXIT /B 0
)
IF ERRORLEVEL 1 (
  CALL :__ECHO__ Azure Bakup���s�������Ƀp�����[�^�G���[���������܂����B
  EXIT /B %__ERROR_CODE__%
)
CALL :__ECHO__ Azure Backup���s�������������܂����B

:__QUIT__
EXIT /B 0

:__ECHO__
SET __TIME__=%TIME:~0,8%
ECHO [%DATE% %__TIME__: =0%] %*
ECHO [%DATE% %__TIME__: =0%] %* >>"%__LOGFILE__%"
EXIT /B 0