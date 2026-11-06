# strix-halo-comfyui-bootstrap

**Windows + AMD Strix Halo（Ryzen AI MAX / Radeon 8060S，gfx1151）一键安装 ComfyUI。**

官方 ComfyUI Windows 便携版自带的是 CUDA 版 PyTorch，在 AMD 核显上完全用不了（`torch.cuda.is_available()` 永远是 `False`，出图会悄悄退回 CPU，实测慢约 10 倍）。这个脚本把踩过的坑打包成一步：

- 下载官方 ComfyUI 便携版并解压（Windows 自带 `tar.exe` 就能读 `.7z`）；
- 把内置 CUDA 版 torch 换成 **ROCm 7.13（gfx1151）Windows 轮子**；
- 校验 `torch.cuda.is_available()` 真的变成 `True` 并打印设备名；
- 生成启动脚本 `Start-ComfyUI.cmd`，附带一个可选的**空闲退出守护** `supervise.js`。

> 社区工具，与 ComfyUI / AMD / DeepSeek 官方无关。

## 背景

Strix Halo（Ryzen AI MAX / Radeon 8060S）是当下最适合本地跑生成式工作负载的消费级机器之一：16 个 Zen 5 核心、40 组 RDNA 3.5 CU、最高 128GB 统一内存。但它不是 CUDA 机器，而整套 ComfyUI Windows 分发包都假设你有一张 NVIDIA 卡。

于是流程注定走不通：

1. 装官方 ComfyUI 便携版；
2. 它自带的是 `torch ....+cu130`；
3. `torch.cuda.is_available()` 返回 `False`；
4. ComfyUI 悄悄退回 CPU；
5. 每一张图都比该有的速度慢约 10 倍（实测同一工作流：CPU 257 秒 vs GPU 27 秒）。

手动修复相当于做一次小型调研：找到 `gfx1151` 对应的 ROCm nightly 索引、挑**同一天构建**的 `torch`/`torchvision`、装 `rocm-sdk-*` 运行库、再验证设备真的可见。这个仓库把这些调研固化成一条命令，让下一个 Strix Halo 用户不用再踩一遍。

## 这个项目解决什么

- **把「能跑」变成「跑对」**：同一工作流从 257 秒降到 27 秒（9.5×），这是本项目最直接的意义；
- **减少一次性研究成本**：ROCm 索引、版本配对、运行库依赖这些信息散落在各处，这里一次性说清；
- **让显存/内存按需占用**：附带的 `supervise.js` 支持「用图才启动、空闲 30 分钟自动退出」，不生成时 RAM/显存归零；
- **可复现的基准与排错**：`docs/BENCHMARK.md` 给出完整测试条件，`docs/TROUBLESHOOTING.md` 覆盖最常见四个坑。

## 为什么需要它

在 Strix Halo 上按官方文档装完，`python -c "import torch; print(torch.__version__, torch.cuda.is_available())"` 得到的是：

```
2.14.1+cu130 False
```

想用上 iGPU 得自己解决：找对 `gfx1151` 的 ROCm nightly 索引、挑**同一天构建**的 `torch` / `torchvision`（版本错配会报 `torchvision::nms` 不存在）、装 `rocm-sdk-core` 与 `rocm-sdk-libraries-gfx1151` 运行库、最后验证设备可见。本仓库就是把这四步固化下来。

## 环境要求

- Windows 10/11 x64
- AMD Ryzen AI MAX（Strix Halo，`gfx1151`）；其它 gfx 目标可用 `-RocmIndex` 覆盖
- 约 10 GB 空闲磁盘（便携版 ~2 GB + torch ROCm ~4 GB + 模型另算）
- PowerShell 5.1+

## 快速开始

```powershell
git clone https://github.com/nizhouding-tech/strix-halo-comfyui-bootstrap.git
cd strix-halo-comfyui-bootstrap
powershell -ExecutionPolicy Bypass -File .\scripts\Install-ComfyUI.ps1 -InstallRoot D:\ComfyUI
```

装完后：

```powershell
D:\ComfyUI\Start-ComfyUI.cmd          # 前台启动，日志在 D:\ComfyUI\logs
# 或者：懒启动 + 30 分钟空闲自动退出
node D:\ComfyUI\supervise.js --port 8188 --idle-min 30
```

## 参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `-InstallRoot` | `D:\ComfyUI` | 安装目录 |
| `-TorchBackend` | `rocm` | `rocm` / `directml` / `cpu` |
| `-RocmIndex` | `https://rocm.nightlies.amd.com/v2/gfx1151/` | 轮子索引 |
| `-TorchVersion` | `2.10.0+rocm7.13.0a20260512` | 固定 torch 构建 |
| `-TorchVisionVersion` | `0.25.0+rocm7.13.0a20260512` | 必须与 torch 同日构建 |
| `-Port` | `8188` | ComfyUI 端口 |
| `-SkipDownload` | 关 | 复用已下载的归档 |
| `-Force` | 关 | 强制重下 / 重装 |

## 实测数据

| 硬件 | ComfyUI | PyTorch | 任务 | 耗时 |
|---|---|---|---|---|
| Ryzen AI MAX+ 395 / Radeon 8060S / 64GB 统一内存 | 0.44.0 | 2.10.0+rocm7.13 | Qwen-Image-2.1 int8，512×512，8 步 | **27 秒** |
| 同上 | 同上 | 同上 | Qwen-Image-2.1 int8，1024×1536，25 步 | **245 秒** |
| 同上（纯 CPU） | 0.44.0 | 2.14.1+cu130（无 GPU） | 512×512，8 步 | 257 秒 |

细节见 [docs/BENCHMARK.md](docs/BENCHMARK.md)。

## 懒启动 / 空闲退出

`supervise.js` 是一个零依赖的 Node 守护进程（Node 20+）：

- 先探 `http://127.0.0.1:<port>/system_stats`，已在跑就退出；
- 不在跑就启动 ComfyUI，等它就绪；
- 每 15 秒看 `/queue` 和 `/history`，连续 `--idle-min` 分钟没有生成活动，就 `taskkill /T /F` 杀掉整棵 Python 进程树；
- 单实例锁 `.supervisor.lock`，并发调用不会起两个实例。

它不依赖任何智能体/插件，可以和任何驱动 ComfyUI 的工具组合。

## 排错

见 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)。最常见的两个：

- `torch.cuda.is_available()` 仍是 `False` → CUDA 版没换掉，加 `-Force` 重跑；
- `operator torchvision::nms does not exist` → torch / torchvision 版本不配对，换同日构建。

## 联系

- 邮箱：**nizhouding@gmail.com** / **1005245828@qq.com**
- GitHub：[@nizhouding-tech](https://github.com/nizhouding-tech)
- 欢迎 issue 与 PR；反馈问题时请附上 ComfyUI 版本、torch 版本，以及
  `python -c "import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0))"` 的输出。

## 许可

MIT © 2026 Zhouding Jeff Ni ([@nizhouding-tech](https://github.com/nizhouding-tech))
