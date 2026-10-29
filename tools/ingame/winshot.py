"""Capture the BeamNG window as you see it, HUD included: python tools/ingame/winshot.py OUT.jpg [--width 1600]

The game's own MCP screenshots leave out the imgui layer (the minimap's roads and the car arrow), so the README's
screenshots (docs/images) are window captures: the window's client area, no title bar, saved as a JPEG, optionally
scaled to --width. `--crop X,Y,W,H` (in window pixels) keeps part of it. Windows only (PowerShell and
System.Drawing); the game window must be visible on screen, since it copies what's on the screen.
"""
import argparse
import subprocess
import sys
from pathlib import Path

SCRIPT = r'''
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public class RaWinShot {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
}
'@
# the game's own window ("BeamNG.drive - 0.40..."), not the launcher's ("BeamNG v0.40 Launcher")
$p = Get-Process | Where-Object { $_.MainWindowTitle -like 'BeamNG.drive - *' } | Select-Object -First 1
if (-not $p) { Write-Error 'no BeamNG window'; exit 1 }
$r = New-Object RaWinShot+RECT; [RaWinShot]::GetClientRect($p.MainWindowHandle, [ref]$r) | Out-Null
$o = New-Object RaWinShot+POINT; [RaWinShot]::ClientToScreen($p.MainWindowHandle, [ref]$o) | Out-Null
$w = $r.R - $r.L; $h = $r.B - $r.T
$full = New-Object System.Drawing.Bitmap $w, $h
[System.Drawing.Graphics]::FromImage($full).CopyFromScreen($o.X, $o.Y, 0, 0, (New-Object System.Drawing.Size $w, $h))
$cx, $cy, $cw, $ch = __CROP__
if ($cw -le 0) { $cw = $w - $cx }; if ($ch -le 0) { $ch = $h - $cy }
$tw = __WIDTH__; if ($tw -le 0 -or $tw -gt $cw) { $tw = $cw }; $th = [int]($ch * $tw / $cw)
$out = New-Object System.Drawing.Bitmap $tw, $th
$g = [System.Drawing.Graphics]::FromImage($out)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($full, (New-Object System.Drawing.Rectangle 0, 0, $tw, $th), (New-Object System.Drawing.Rectangle $cx, $cy, $cw, $ch), [System.Drawing.GraphicsUnit]::Pixel)
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), ([long]__QUALITY__)
$out.Save('__OUT__', $codec, $ep)
"$($w)x$($h) window -> $($tw)x$($th)"
'''


def capture(out, width=0, crop=(0, 0, 0, 0), quality=85):
    """Save the game window's client area (part of it with `crop` = x, y, w, h) to `out` as a JPEG."""
    script = (SCRIPT.replace("__CROP__", ", ".join(str(int(v)) for v in crop)).replace("__WIDTH__", str(int(width)))
              .replace("__QUALITY__", str(int(quality))).replace("__OUT__", str(Path(out).resolve()).replace("'", "''")))
    res = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
                         capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(res.stderr.strip() or res.stdout.strip())
    return res.stdout.strip()


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("out")
    p.add_argument("--width", type=int, default=0, help="scale to this width (default: as captured)")
    p.add_argument("--crop", default="0,0,0,0", help="X,Y,W,H in window pixels (0 = to the edge)")
    p.add_argument("--quality", type=int, default=85)
    a = p.parse_args(argv)
    print(capture(a.out, a.width, tuple(int(v) for v in a.crop.split(",")), a.quality))


if __name__ == "__main__":
    main(sys.argv[1:])
