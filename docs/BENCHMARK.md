# Benchmarks

All numbers below were measured on one machine with `ComfyUI 0.44.0` and a **single checkpoint**,
using the same workflow JSON and an idle machine (no other GPU work).

## Test machine

| Item | Value |
|---|---|
| CPU | AMD Ryzen AI MAX+ 395 (16C/32T) |
| GPU | AMD Radeon 8060S (RDNA 3.5, gfx1151), 40 CU |
| Memory | 64 GB unified (shared with the GPU) |
| OS | Windows 11 |
| ComfyUI | 0.44.0 (Windows portable) |
| PyTorch | 2.10.0+rocm7.13.0a20260512 (gfx1151 wheels) |
| Python | 3.13.14 (portable) |

## Model under test

Qwen-Image-2.1 (7B DiT) int8_convrot + Qwen3-VL 8B text encoder (int8) + Qwen-Image-2.1 VAE.
Weights: 6.76 GB + 8.71 GB + 0.63 GB. Sampler `euler` / `simple`.

## Results

| Workload | Device | Time |
|---|---|---|
| 512 × 512, 8 steps, CFG 1 | Radeon 8060S (ROCm) | **27 s** |
| 512 × 512, 8 steps, CFG 1 | CPU (16 threads) | 257 s |
| 1024 × 1536, 25 steps, CFG 3 | Radeon 8060S (ROCm) | **245 s** |

Notes:

- The GPU runs are ~9.5× faster than CPU on the same workflow.
- The 1024 × 1536 number **includes** the first model load in that server session; repeats with the
  same process are somewhat faster.
- Peak VRAM usage during 1024 × 1536 generation is about 17 GB of the 64 GB unified memory pool.
- `cfg_scale: 1` roughly halves generation time but disables the negative prompt.

## Reproduce

```powershell
.\scripts\Install-ComfyUI.ps1 -InstallRoot D:\ComfyUI
node D:\ComfyUI\supervise.js --port 8188 --idle-min 30
# then submit the same workflow JSON to http://127.0.0.1:8188/prompt
```

Environment details are printed at startup:

```
Total VRAM 65176 MB, total RAM 65176 MB
Device: cuda:0 AMD Radeon(TM) 8060S Graphics : native
```
