@echo off
setlocal enabledelayedexpansion

echo ============================================
echo  FFB Wheel Control v3.0 - Build Script
echo ============================================
echo  Requires: JDK 8+ (JAVA_HOME) and Python 3 on PATH
echo ============================================

set "JDKBIN=%JAVA_HOME%\bin"
set "JAVAC=%JDKBIN%\javac.exe"
set "JAR=%JDKBIN%\jar.exe"

set "LIB=%~dp0lib"
set "SRCDIR=%~dp0"
set "SRCDIR=%SRCDIR:~0,-1%"
set "BUILD=%~dp0build"
set "OUT=%~dp0WheelControl"
set "MAIN=wheel_control_v3"

echo.
echo [1/3] Preprocessing .pde -^> Java ...
if exist "%BUILD%" rmdir /s /q "%BUILD%"
mkdir "%BUILD%"
python "%~dp0pde2java.py" "%SRCDIR%" "wheel_control_v2.pde" "%MAIN%.java" > "%BUILD%\preprocess.log"
if %ERRORLEVEL% neq 0 (
    echo PREPROCESS FAILED
    type "%BUILD%\preprocess.log"
    pause
    exit /b 1
)
move /y "%~dp0%MAIN%.java" "%BUILD%\%MAIN%.java" >nul

echo.
echo [2/3] Compiling ...
set "CP=%LIB%\core.jar;%LIB%\controlP5.jar;%LIB%\GameControlPlus.jar;%LIB%\serial.jar;%LIB%\Sprites.jar;%LIB%\jssc.jar;%LIB%\native-lib-loader.jar;%LIB%\slf4j-api.jar;%LIB%\slf4j-nop.jar"
"%JAVAC%" -encoding UTF-8 --release 8 -nowarn -cp "%CP%" -d "%BUILD%" "%BUILD%\%MAIN%.java" 2>"%BUILD%\compile_errors.txt"
if %ERRORLEVEL% neq 0 (
    echo COMPILATION FAILED:
    type "%BUILD%\compile_errors.txt"
    pause
    exit /b 1
)
echo OK

echo.
echo [3/3] Assembling portable app (run with your own JRE) ...
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%"
mkdir "%OUT%\lib"
mkdir "%OUT%\data"

set "MANIFEST=%BUILD%\MANIFEST.MF"
(
echo Manifest-Version: 1.0
echo Main-Class: %MAIN%
) > "%MANIFEST%"
"%JAR%" cfm "%BUILD%\%MAIN%.jar" "%MANIFEST%" -C "%BUILD%" . 2>nul
copy "%BUILD%\%MAIN%.jar" "%OUT%\lib\" >nul
copy "%LIB%\*.jar" "%OUT%\lib\" >nul
copy "%LIB%\*.dll" "%OUT%\lib\" >nul 2>nul

rem --- Launcher BAT (uses java from JAVA_HOME — install a JRE/JDK 8+ to run) ---
(
echo @echo off
echo cd /d "%%~dp0"
echo start "" "%%JAVA_HOME%%\bin\javaw.exe" -Djava.library.path=lib -cp "lib\core.jar;lib\controlP5.jar;lib\GameControlPlus.jar;lib\serial.jar;lib\Sprites.jar;lib\jssc.jar;lib\native-lib-loader.jar;lib\slf4j-api.jar;lib\slf4j-nop.jar;lib\%MAIN%.jar" %MAIN%
) > "%OUT%\WheelControl.bat"

echo.
echo ============================================
echo  BUILD COMPLETE!
echo ============================================
echo  DIR:  %OUT%\
echo  RUN:  %OUT%\WheelControl.bat  (needs JAVA_HOME set to a JRE/JDK 8+)
echo.
echo  Want a real standalone .exe with no Java install required?
echo  Run build-exe.bat instead (uses jpackage, JDK 14+).
echo ============================================
rmdir /s /q "%BUILD%" 2>nul
pause
