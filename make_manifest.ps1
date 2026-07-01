param(
    [Parameter(Mandatory=$true)][string]$MainClass,
    [Parameter(Mandatory=$true)][string]$OutFile,
    [Parameter(Mandatory=$true)][string]$ClassPathJars # single space-separated string, e.g. "a.jar b.jar c.jar" - avoids CLI array-binding ambiguity when invoked from cmd/bash
)

# jpackage has no --class-path flag; an app-image launcher only runs the jar named by
# --main-jar, so any other dependency jars have to be listed in that jar's own manifest
# Class-Path attribute (space-separated, paths relative to the jar - they sit next to it
# in app/ since build-exe.bat copies the whole lib/ folder there). Each physical manifest
# line, including continuations, is capped at 72 bytes by the JAR spec; continuation lines
# must start with exactly one literal space - PowerShell handles that cleanly where batch's
# `echo` cannot.

$cp = $ClassPathJars.Trim()
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('Manifest-Version: 1.0')
$lines.Add("Main-Class: $MainClass")

$prefix = 'Class-Path: '
$firstChunkLen = [Math]::Min(72 - $prefix.Length, $cp.Length)
$lines.Add($prefix + $cp.Substring(0, $firstChunkLen))
$rest = $cp.Substring($firstChunkLen)
while ($rest.Length -gt 0) {
    $take = [Math]::Min(71, $rest.Length)
    $lines.Add(' ' + $rest.Substring(0, $take))
    $rest = $rest.Substring($take)
}

$text = [string]::Join("`r`n", $lines) + "`r`n"
[System.IO.File]::WriteAllText($OutFile, $text, [System.Text.Encoding]::ASCII)
