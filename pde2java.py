#!/usr/bin/env python3
"""
Convert Processing .pde files to a single .java file.
Handles Processing-specific syntax: int(), float(), str(), byte(), constrain(), round(), map(), nf(), etc.
"""
import os
import re
import sys

SRC_DIR = sys.argv[1] if len(sys.argv) > 1 else "."
MAIN_FILE = sys.argv[2] if len(sys.argv) > 2 else "wheel_control_v2.pde"
OUT_FILE = sys.argv[3] if len(sys.argv) > 3 else "wheel_control_v3.java"
CLASS_NAME = os.path.splitext(OUT_FILE)[0]

# Collect all .pde files
pde_files = []
for f in sorted(os.listdir(SRC_DIR)):
    if f.endswith(".pde"):
        pde_files.append(os.path.join(SRC_DIR, f))

def convert_processing_syntax(code):
    """Convert Processing-specific Java syntax to standard Java."""

    # ---- Type replacements ----
    # Replace 'color' as a type declaration (not function call)
    # color[] -> int[]
    code = re.sub(r'\bcolor\b(\s*\[)', r'int\1', code)
    # color variable = ... ; color param, etc
    code = re.sub(r'\bcolor\b(\s+\w+\s*[=;,)])', r'int\1', code)
    # color return type: color methodName(
    code = re.sub(r'\bcolor\b(\s+\w+\s*\()', r'int\1', code)

    # ---- Function call conversions (avoid double-wrapping PApplet.) ----
    # Use a sentinel to avoid double conversion
    SENTINEL = "___PP___"

    # int(x) -> PApplet.parseInt(x)
    code = re.sub(r'(?<!\w)(?<!\[)(?<!\.)(?<!' + SENTINEL + r')int\(([^)]+)\)', SENTINEL + r'parseInt(\1)', code)

    # float(x) -> PApplet.parseFloat(x)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')float\(([^)]+)\)', SENTINEL + r'parseFloat(\1)', code)

    # str(x) -> PApplet.str(x)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')str\(([^)]+)\)', SENTINEL + r'str(\1)', code)

    # byte(x) -> (byte)(x)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')byte\(([^)]+)\)', r'(byte)(\1)', code)

    # constrain(x, a, b) -> PApplet.constrain(x, a, b)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')constrain\(([^,]+),\s*([^,]+),\s*([^)]+)\)', SENTINEL + r'constrain(\1, \2, \3)', code)

    # round(x) -> PApplet.round(x)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')round\(([^)]+)\)', SENTINEL + r'round(\1)', code)

    # map(x, a, b, c, d) -> PApplet.map(x, a, b, c, d)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')map\(([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^)]+)\)', SENTINEL + r'map(\1, \2, \3, \4, \5)', code)

    # nf(x, d) -> PApplet.nf(x, d)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')nf\(([^,]+),\s*([^)]+)\)', SENTINEL + r'nf(\1, \2)', code)

    # nf(x, d, f) -> PApplet.nf(x, d, f)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')nf\(([^,]+),\s*([^,]+),\s*([^)]+)\)', SENTINEL + r'nf(\1, \2, \3)', code)

    # pow(x, y) -> PApplet.pow(x, y)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')pow\(([^,]+),\s*([^)]+)\)', SENTINEL + r'pow(\1, \2)', code)

    # sqrt(x) -> PApplet.sqrt(x)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')sqrt\(([^)]+)\)', SENTINEL + r'sqrt(\1)', code)

    # abs(x) -> PApplet.abs(x)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')abs\(([^)]+)\)', SENTINEL + r'abs(\1)', code)

    # min(x, y) -> PApplet.min(x, y)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')min\(([^,]+),\s*([^)]+)\)', SENTINEL + r'min(\1, \2)', code)

    # max(x, y) -> PApplet.max(x, y)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')max\(([^,]+),\s*([^)]+)\)', SENTINEL + r'max(\1, \2)', code)

    # floor(x) -> PApplet.floor(x)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')floor\(([^)]+)\)', SENTINEL + r'floor(\1)', code)

    # ceil(x) -> PApplet.ceil(x)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')ceil\(([^)]+)\)', SENTINEL + r'ceil(\1)', code)

    # lerp(a, b, t) -> PApplet.lerp(a, b, t)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')lerp\(([^,]+),\s*([^,]+),\s*([^)]+)\)', SENTINEL + r'lerp(\1, \2, \3)', code)

    # hex(x) -> PApplet.hex(x)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')hex\(([^)]+)\)', SENTINEL + r'hex(\1)', code)

    # unhex(x) -> PApplet.unhex(x)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')unhex\(([^)]+)\)', SENTINEL + r'unhex(\1)', code)

    # radians(x) -> PApplet.radians(x)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')radians\(([^)]+)\)', SENTINEL + r'radians(\1)', code)

    # degrees(x) -> PApplet.degrees(x)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')degrees\(([^)]+)\)', SENTINEL + r'degrees(\1)', code)

    # char(x) -> (char)(x)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')char\(([^)]+)\)', r'(char)(\1)', code)

    # trim(x) -> PApplet.trim(x)
    code = re.sub(r'(?<!\w)(?<!' + SENTINEL + r')trim\(([^)]+)\)', SENTINEL + r'trim(\1)', code)

    # Now replace sentinel with PApplet.
    code = code.replace(SENTINEL, 'PApplet.')

    # ---- Float literal suffix (Java needs f for float) ----
    # Add 'f' suffix to float literals that don't already have it
    # Match: digits.digits (not followed by f/F/e/E)
    # Be careful not to affect int() or string literals
    # Only in specific contexts where we know it's a float literal
    code = re.sub(r'(?<![a-zA-Z_\d])(\d+\.\d+)(?![fFeE\d])', r'\1f', code)

    # Remove Processing preprocessor lines
    code = re.sub(r'^\s*#.*$', '', code, flags=re.MULTILINE)

    # Processing key constants -> Java KeyEvent constants (use word boundaries to avoid TAB_DASHBOARD etc)
    code = re.sub(r'\bESCAPE\b', 'java.awt.event.KeyEvent.VK_ESCAPE', code)
    code = re.sub(r'\bBACKSPACE\b', 'java.awt.event.KeyEvent.VK_BACK_SPACE', code)
    code = re.sub(r'\bDELETE\b', 'java.awt.event.KeyEvent.VK_DELETE', code)
    code = re.sub(r'(?<![A-Za-z_])TAB(?![A-Za-z_])', 'java.awt.event.KeyEvent.VK_TAB', code)
    code = re.sub(r'\bENTER\b', 'java.awt.event.KeyEvent.VK_ENTER', code)
    code = re.sub(r'\bRETURN\b', 'java.awt.event.KeyEvent.VK_ENTER', code)

    # Processing 'parent' -> 'this' for PApplet context
    code = re.sub(r'\bparent\b', 'this', code)

    # Add 'public' to Processing lifecycle methods (only if not already public)
    code = re.sub(r'(?<!public )void settings\(\)', 'public void settings()', code)
    code = re.sub(r'(?<!public )void setup\(\)', 'public void setup()', code)
    code = re.sub(r'(?<!public )void draw\(\)', 'public void draw()', code)
    code = re.sub(r'(?<!public )void mousePressed\(\)', 'public void mousePressed()', code)
    code = re.sub(r'(?<!public )void mouseReleased\(\)', 'public void mouseReleased()', code)
    code = re.sub(r'(?<!public )void mouseDragged\(\)', 'public void mouseDragged()', code)
    code = re.sub(r'(?<!public )void mouseWheel\(MouseEvent', 'public void mouseWheel(MouseEvent', code)
    code = re.sub(r'(?<!public )void keyPressed\(\)', 'public void keyPressed()', code)
    code = re.sub(r'(?<!public )void keyReleased\(\)', 'public void keyReleased()', code)
    code = re.sub(r'(?<!public )void exit\(\)', 'public void exit()', code)
    code = re.sub(r'(?<!public )void serialEvent\(Serial', 'public void serialEvent(Serial', code)

    return code


# Read main file
main_path = os.path.join(SRC_DIR, MAIN_FILE)
with open(main_path, "r", encoding="utf-8") as f:
    main_content = f.read()

# Extract imports from main file
imports = []
imports.append("import processing.core.*;")
imports.append("import processing.data.*;")
imports.append("import processing.event.*;")
imports.append("import processing.opengl.*;")
imports.append("import org.gamecontrolplus.gui.*;")
imports.append("import org.gamecontrolplus.*;")
imports.append("import net.java.games.input.*;")
imports.append("import processing.serial.*;")
imports.append("import sprites.*;")
imports.append("import sprites.maths.*;")
imports.append("import sprites.utils.*;")
imports.append("import controlP5.*;")
imports.append("import java.util.*;")
imports.append("import static javax.swing.JOptionPane.*;")
imports.append("import javax.swing.JFrame.*;")
imports.append("import java.io.InputStreamReader;")
imports.append("import java.io.BufferedReader;")
imports.append("import java.util.HashMap;")
imports.append("import java.util.ArrayList;")
imports.append("import java.io.File;")
imports.append("import java.io.PrintWriter;")
imports.append("import java.io.InputStream;")
imports.append("import java.io.OutputStream;")
imports.append("import java.io.IOException;")
imports.append("import java.io.FileInputStream;")
imports.append("import java.io.FileOutputStream;")
imports.append("import java.io.ByteArrayOutputStream;")
imports.append("import java.net.URL;")
imports.append("import java.net.HttpURLConnection;")
imports.append("import java.util.zip.ZipInputStream;")
imports.append("import java.util.zip.ZipEntry;")
imports.append("import java.nio.file.Files;")
imports.append("import java.nio.file.StandardCopyOption;")

# Collect content from all .pde files (skip main)
other_content = []
for pf in pde_files:
    if os.path.basename(pf) == MAIN_FILE:
        continue
    with open(pf, "r", encoding="utf-8") as f:
        content = f.read()
    content = convert_processing_syntax(content)
    other_content.append(f"// ---- {os.path.basename(pf)} ----\n{content}")

# Process main file content
main_body = main_content

# Remove import lines
import_pattern = r'^import\s+.*?;\s*$'
main_body = re.sub(import_pattern, '', main_body, flags=re.MULTILINE)

# Remove Processing-specific preprocessor directives
main_body = re.sub(r'^\s*#.*$', '', main_body, flags=re.MULTILINE)

# Remove the outer comment block
main_body = re.sub(r'/\*.*?\*/', '', main_body, flags=re.DOTALL)

# Convert Processing syntax
main_body = convert_processing_syntax(main_body)

# Clean up
main_body = main_body.strip()

# Build the Java file
output = []

# Imports
for imp in imports:
    output.append(imp)
output.append("")

# Class declaration
output.append(f"public class {CLASS_NAME} extends PApplet {{")
output.append("")

# Add all other .pde files content
for oc in other_content:
    output.append(oc)
    output.append("")

# Add main file content
output.append("// ---- main file ----")
output.append(main_body)
output.append("")

# Close class
output.append("}")

# Write output
out_path = os.path.join(SRC_DIR, OUT_FILE)
with open(out_path, "w", encoding="utf-8") as f:
    f.write("\n".join(output))

print(f"Generated {out_path}")
print(f"Total lines: {len(output)}")
