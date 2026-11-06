# Troubleshooting

## `torch.cuda.is_available()` is `False`

The bundled CUDA build is still installed. Re-run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-ComfyUI.ps1 -TorchBackend rocm -Force
```

Check what is actually installed:

```powershell
D:\ComfyUI\ComfyUI_windows_portable\python_embeded\python.exe -m pip list | findstr /i "torch rocm"
```

You should see `torch 2.10.0+rocm7.13.0a...`, `torchvision 0.25.0+rocm7.13.0a...`,
`rocm-sdk-core`, `rocm-sdk-libraries-gfx1151`.

## `operator torchvision::nms does not exist`

`torch` and `torchvision` were not built together. Install a pair with the **same date suffix**:

```powershell
$py = 'D:\ComfyUI\ComfyUI_windows_portable\python_embeded\python.exe'
& $py -m pip install --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ --pre --no-cache-dir `
  'torch==2.10.0+rocm7.13.0a20260512' 'torchvision==0.25.0+rocm7.13.0a20260512'
```

## `ImportError: DLL load failed` when importing torch

The ROCm runtime wheels are missing or the wrong version. Reinstall the pair above; pip will pull
`rocm-sdk-core` and `rocm-sdk-libraries-gfx1151` as dependencies.

## Download is very slow or times out

- The archive is ~2 GB from GitHub. Reuse a manual download:

  ```powershell
  .\scripts\Install-ComfyUI.ps1 -InstallRoot D:\ComfyUI -SkipDownload
  ```

  (put `ComfyUI_windows_portable_nvidia.7z` in `D:\ComfyUI\downloads` first)
- A GitHub mirror/proxy can be used for the archive; the script does not care where it came from.

## `tar.exe not found`

Windows 10 1803+ ships `bsdtar` as `tar.exe`. On older builds, extract the `.7z` with 7-Zip into
the install root and re-run with `-SkipDownload`.

## Port already in use

ComfyUI is probably already running (maybe a second instance). Check:

```powershell
curl.exe -s http://127.0.0.1:8188/system_stats
```

Either use the running instance, or start with another port (`Start-ComfyUI.cmd` is generated with
the `-Port` you passed; `supervise.js --port ...` matches it).

## First generation takes much longer

Model weights (tens of GB) are loaded lazily on the first prompt of a server session. Subsequent
generations reuse them. `supervise.js` keeps the server alive while it is being used and only
stops it after the idle timeout, so short pauses do not force a reload.

## Out of memory / device lost

Lower the resolution or step count; on unified-memory machines the OS may also be under pressure
from other apps. A 1024 × 1536 run needs roughly 17 GB for the Qwen-Image-2.1 int8 stack.

## ROCm does not support my GPU

The default index is `gfx1151` (Strix Halo). For other targets pass a matching index:

```powershell
.\scripts\Install-ComfyUI.ps1 -RocmIndex https://rocm.nightlies.amd.com/v2/gfx1201/
```

and pin `-TorchVersion` / `-TorchVisionVersion` to builds that exist there.
