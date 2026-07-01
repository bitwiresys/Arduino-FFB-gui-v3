@echo off
setlocal enabledelayedexpansion

echo ============================================
echo  FFB Wheel Control v3.0 - Standalone EXE Build
echo ============================================
echo  Requires: JDK 14+ (JAVA_HOME, for jpackage) and Python 3 on PATH
echo ============================================

set "JDKBIN=%JAVA_HOME%\bin"
set "JAVAC=%JDKBIN%\javac.exe"
set "JAR=%JDKBIN%\jar.exe"
set "JPACKAGE=%JDKBIN%\jpackage.exe"

set "LIB=%~dp0lib"
set "SRCDIR=%~dp0"
set "SRCDIR=%SRCDIR:~0,-1%"
set "BUILD=%~dp0build"
set "OUT=%~dp0WheelControlApp"
set "MAIN=wheel_control_v3"

echo.
echo [1/4] Preprocessing .pde -^> Java ...
if exist "%BUILD%" rmdir /s /q "%BUILD%"
mkdir "%BUILD%"
python "%~dp0pde2java.py" "%SRCDIR%" "wheel_control_v2.pde" "%MAIN%.java" > "%BUILD%\preprocess.log"
if %ERRORLEVEL% neq 0 (
    echo PREPROCESS FAILED
    type "%BUILD%\preprocess.log"
    if not defined CI pause
    exit /b 1
)
move /y "%~dp0%MAIN%.java" "%BUILD%\%MAIN%.java" >nul

echo.
echo [2/4] Compiling ...
set "CP=%LIB%\core.jar;%LIB%\controlP5.jar;%LIB%\GameControlPlus.jar;%LIB%\serial.jar;%LIB%\Sprites.jar;%LIB%\jssc.jar;%LIB%\native-lib-loader.jar;%LIB%\slf4j-api.jar;%LIB%\slf4j-nop.jar"
"%JAVAC%" -encoding UTF-8 --release 8 -nowarn -cp "%CP%" -d "%BUILD%" "%BUILD%\%MAIN%.java" 2>"%BUILD%\compile_errors.txt"
if %ERRORLEVEL% neq 0 (
    echo COMPILATION FAILED:
    type "%BUILD%\compile_errors.txt"
    if not defined CI pause
    exit /b 1
)
echo OK

echo.
echo [3/4] Packaging jar ...
(
echo Manifest-Version: 1.0
echo Main-Class: %MAIN%
) > "%BUILD%\MANIFEST.MF"
"%JAR%" cfm "%BUILD%\%MAIN%.jar" "%BUILD%\MANIFEST.MF" -C "%BUILD%" . 2>nul

echo.
echo [4/4] Building standalone exe (jpackage, bundles its own Java runtime) ...
if exist "%OUT%" rmdir /s /q "%OUT%"
set "JPKG_IN=%BUILD%\jpkg_input"
mkdir "%JPKG_IN%"
copy "%BUILD%\%MAIN%.jar" "%JPKG_IN%\" >nul
copy "%LIB%\*.jar" "%JPKG_IN%\" >nul
copy "%LIB%\*.dll" "%JPKG_IN%\" >nul 2>nul

"%JPACKAGE%" --type app-image --input "%JPKG_IN%" --dest "%~dp0" --name "WheelControlApp" --main-jar "%MAIN%.jar" --main-class %MAIN% --class-path "core.jar;controlP5.jar;GameControlPlus.jar;serial.jar;Sprites.jar;jssc.jar;native-lib-loader.jar;slf4j-api.jar;slf4j-nop.jar" --java-options "-Djava.library.path=$APPDIR" --app-version "3.0.0" --vendor "FFB Wheel" --description "Arduino FFB Wheel Control Panel"
if %ERRORLEVEL% neq 0 (
    echo JPACKAGE FAILED
    if not defined CI pause
    exit /b 1
)
mkdir "%OUT%\data" 2>nul

echo.
echo ============================================
echo  BUILD COMPLETE!
echo ============================================
echo  DIR:  %OUT%\
echo  RUN:  %OUT%\WheelControlApp.exe   (no Java install needed)
echo ============================================
rmdir /s /q "%BUILD%" 2>nul
if not defined CI pause
