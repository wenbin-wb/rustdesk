@if "%DEBUG%" == "" @echo off
@rem ##########################################################################
@rem
@rem  Hvigor startup script for Windows
@rem
@rem ##########################################################################

@rem Set local scope for the variables with windows NT shell
if "%OS%"=="Windows_NT" setlocal

set DIRNAME=%~dp0
if "%DIRNAME%" == "" set DIRNAME=.
set APP_BASE_NAME=%~n0
set APP_HOME=%DIRNAME%

@rem Resolve any "." and ".." in APP_HOME to make it shorter.
for %%i in ("%APP_HOME%") do set APP_HOME=%%~fi

set WRAPPER_MODULE_PATH=%DIRNAME%\hvigorw.js
set NODE_EXE=node.exe
@rem set NODE_OPTS="--max-old-space-size=8192 --expose-gc"

if not defined DEVECO_SDK_HOME if exist "D:\Program Files\Huawei\DevEco Studio\sdk" set DEVECO_SDK_HOME=D:\Program Files\Huawei\DevEco Studio\sdk
if not defined JAVA_HOME if exist "D:\Program Files\Huawei\DevEco Studio\jbr" set JAVA_HOME=D:\Program Files\Huawei\DevEco Studio\jbr
if defined JAVA_HOME set PATH=%JAVA_HOME%\bin;%PATH%
if not defined NODE_HOME if exist "D:\Program Files\Huawei\DevEco Studio\tools\node" set NODE_HOME=D:\Program Files\Huawei\DevEco Studio\tools\node
if not defined NODE_PATH set NODE_PATH=%APP_HOME%\node_modules;D:\Program Files\Huawei\DevEco Studio\tools\hvigor
if exist "D:\Program Files\Huawei\DevEco Studio\tools\hvigor\hvigor\bin\hvigor.js" set WRAPPER_MODULE_PATH=D:\Program Files\Huawei\DevEco Studio\tools\hvigor\hvigor\bin\hvigor.js

goto start

:start
if not defined NODE_OPTS set NODE_OPTS="--"

@rem Find node.exe
if defined NODE_HOME goto findNodeFromNodeHome

%NODE_EXE% --version >NUL 2>&1
if "%ERRORLEVEL%" == "0" goto execute

echo.
echo ERROR: NODE_HOME is not set and no 'node' command could be found in your PATH.
echo.
echo Please set the NODE_HOME variable in your environment to match the
echo location of your NodeJs installation.

goto fail

:findNodeFromNodeHome
set NODE_HOME=%NODE_HOME:"=%
set NODE_EXE_PATH=%NODE_HOME%/%NODE_EXE%

if exist "%NODE_EXE_PATH%" goto execute
echo.
echo ERROR: NODE_HOME is not set and no 'node' command could be found in your PATH.
echo.
echo Please set the NODE_HOME variable in your environment to match the
echo location of your NodeJs installation.

goto fail

:execute
@rem Execute hvigor
"%NODE_EXE%" "%NODE_OPTS%" "%WRAPPER_MODULE_PATH%" %*

if "%ERRORLEVEL%" == "0" goto hvigorwEnd

:fail
exit /b 1

:hvigorwEnd
if "%OS%" == "Windows_NT" endlocal

:end
