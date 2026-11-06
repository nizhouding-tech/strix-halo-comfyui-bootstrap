# strix-halo-comfyui-bootstrap

One-shot ComfyUI setup for **Windows + AMD Strix Halo (Ryzen AI MAX / Radeon 8060S, gfx1151)**.

The official ComfyUI Windows portable ships a CUDA build of PyTorch, which is useless on an AMD
iGPU. This script downloads the portable build, swaps PyTorch for the **ROCm 7.13 (gfx1151)
Windows wheels**, verifies that the GPU is actually visible, and drops a launcher + an optional
idle-exit supervisor next to it.

> Unofficial community tool. Not affiliated with ComfyUI, AMD or DeepSeek.

## Background

Strix Halo (Ryzen AI MAX, Radeon 8060S) is one of the best consumer machines for local generative
workloads: 16 Zen 5 cores, 40 RDNA 3.5 CUs and up to 128 GB of unified memory. What it is *not* is a
CUDA machine — and the entire ComfyUI Windows distribution assumes NVIDIA.

The result is a predictable dead end:

1. you install the official ComfyUI portable build,
2. it ships `torch ....+cu130`,
3. `torch.cuda.is_available()` is `False`,
4. ComfyUI silently falls back to the CPU,
5. and every generation is ~10× slower than it should be (measured: 257 s vs 27 s for the same
   workflow on this machine).

Fixing it by hand is a research project: find the right ROCm nightly index for `gfx1151`, pick a
`torch`/`torchvision` pair built on the same day, install the `rocm-sdk-*` runtime wheels, and
verify the GPU is actually visible. This repository turns that research into one command, so the
next Strix Halo owner does not have to repeat it.

## Why

On Strix Halo machines the usual "install ComfyUI portable" flow ends with:

```
torch 2.14.1+cu130  cuda_available False
```

and every generation silently runs on the CPU (roughly 10x slower in our measurements).
Getting HIP working by hand means:

- knowing the ROCm nightly index for `gfx1151`,
- picking a **matching** `torch` / `torchvision` pair (they are built together; mismatches throw
  `torchvision::nms` operator errors at import),
- installing the `rocm-sdk-core` + `rocm-sdk-libraries-gfx1151` runtime wheels,
- verifying `torch.cuda.is_available()` actually flips to `True`.

This repo packages exactly those steps.

## Requirements

- Windows 10/11 x64
- AMD Ryzen AI MAX (Strix Halo, `gfx1151`) — other gfx targets need `-RocmIndex` override
- ~10 GB free disk (ComfyUI portable ~2 GB, torch ROCm stack ~4 GB, models extra)
- PowerShell 5.1+ (the script re-launches itself with TLS 1.2 enabled)

## Quick start

```powershell
git clone https://github.com/nizhouding-tech/strix-halo-comfyui-bootstrap.git
cd strix-halo-comfyui-bootstrap
powershell -ExecutionPolicy Bypass -File .\scripts\Install-ComfyUI.ps1 -InstallRoot D:\ComfyUI
```

The script:

1. downloads `ComfyUI_windows_portable_nvidia.7z` from the official release (resumable via `-SkipDownload`),
2. extracts it with `tar.exe` (bsdtar reads 7z),
3. replaces the bundled CUDA torch with the gfx1151 ROCm wheels,
4. verifies `torch.cuda.is_available()` and prints the detected device,
5. writes `Start-ComfyUI.cmd` and `supervise.js` (optional idle-exit supervisor).

Then:

```powershell
D:\ComfyUI\Start-ComfyUI.cmd        # foreground, logs to D:\ComfyUI\logs
# optional: lazy start + auto-exit after 30 idle minutes
node D:\ComfyUI\supervise.js --port 8188 --idle-min 30
```

## Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `-InstallRoot` | `D:\ComfyUI` | Where the portable build and models live |
| `-TorchBackend` | `rocm` | `rocm` / `directml` / `cpu` |
| `-RocmIndex` | `https://rocm.nightlies.amd.com/v2/gfx1151/` | Wheel index |
| `-TorchVersion` | `2.10.0+rocm7.13.0a20260512` | Pin the torch build |
| `-TorchVisionVersion` | `0.25.0+rocm7.13.0a20260512` | Must match the torch build |
| `-Port` | `8188` | ComfyUI port |
| `-SkipDownload` | off | Reuse an already downloaded archive |
| `-Force` | off | Re-download / reinstall even if present |

## Measured on

| Hardware | ComfyUI | PyTorch | Workload | Time |
|---|---|---|---|---|
| Ryzen AI MAX+ 395 / Radeon 8060S / 64 GB unified | 0.44.0 | 2.10.0+rocm7.13 | Qwen-Image-2.1 int8, 512×512, 8 steps | **27 s** |
| same | same | same | Qwen-Image-2.1 int8, 1024×1536, 25 steps | **245 s** |
| same, CPU only | 0.44.0 | 2.14.1+cu130 (CUDA build, no GPU) | 512×512, 8 steps | 257 s |

Full notes: [docs/BENCHMARK.md](docs/BENCHMARK.md).

## Lazy start / idle exit

`supervise.js` is a tiny node supervisor (no dependencies, Node 20+):

- starts ComfyUI if `http://127.0.0.1:<port>/system_stats` is not answering,
- watches `/queue` and `/history` every 15 s,
- kills the whole Python process tree after `--idle-min` minutes without generation activity,
- single-instance lock (`.supervisor.lock`) so concurrent callers never start two servers.

It is deliberately independent of any harness/plugin, so it composes with whatever drives ComfyUI.

```powershell
node D:\ComfyUI\supervise.js --port 8188 --idle-min 30
```

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md). The two most common failures:

- `torch.cuda.is_available() == False` → the CUDA wheels were not replaced; re-run with `-Force`.
- `operator torchvision::nms does not exist` → `torchvision` does not match `torch`; install a pair
  built on the same date.

## Contact

- Email: **nizhouding@gmail.com** / **1005245828@qq.com**
- GitHub: [@nizhouding-tech](https://github.com/nizhouding-tech)
- Issues and PRs are welcome; please include `ComfyUI version`, `torch version` and the output of
  `python -c "import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0))"`.

## License

MIT © 2026 Zhouding Jeff Ni ([@nizhouding-tech](https://github.com/nizhouding-tech))
