# Kokoro 中英文离线语音

## 当前接入

默认使用 Kokoro-82M v1.1-zh int8。中文声音 zf_001（ID 3），英文 af_maple（ID 0）。文字、模型推理和播放均在设备上完成，应用没有模型下载或上传文字的代码；系统声音只在用户明确切换后使用。

仓库中的 `Packages/KokoroRuntime` 封装 sherpa-onnx 1.13.8 C API，链接固定 SHA-256 的 iOS 静态 XCFramework 与 ONNX Runtime 1.28.1。包括 arm64 真机及 arm64/x86_64 模拟器。

第一次获取仓库时运行：

```sh
python3 scripts/prepare_kokoro.py
```

准备脚本需要构建机联网，下载约 196 MB 压缩文件，逐项校验后解压。模型工作目录约 206 MB，运行库目录约 194 MB。模型和运行库由 `.gitignore` 排除，固定版本、下载来源、校验值和声音映射由 `Models/kokoro.lock.json` 跟踪。当前 Mac 已完成准备。重新安装应用时模型随包安装，不需要首次启动后下载。

在 Xcode 打开工程并运行即可。项目已链接本地 Swift 包，以保留文件夹结构的资源方式复制 `Models/Kokoro`，保证中文字典、eSpeak 数据和 FST 规则能定位。缺少模型时显示明确错误，不使用系统声音或云端伪装成功。

## 播放行为

- 推理在 actor 的串行执行器中进行，不占 UI 线程；音频会话、WAV 编码、播放器创建和预加载也在串行后台队列进行。
- 英文每段最多 60 字符、含中文最多 20 字符，优先保留句子与英文单词边界。长页面不会截断，逐段合成和播放；目前段与段之间仍可能有合成等待。
- 语速范围 0.5–1.2；音频缓存键包含文字、声音与语速，最多 12 MB，不落盘。
- 点新的文字、翻页、停止、切后台和音频中断会取消当前请求；原生生成回调检查线程安全取消标记。停止不能在一个 ONNX 算子中间强行终止，因此当前段可能继续计算到回调，但结果不会播放或入缓存。
- 暂停可发生在合成期间，生成的播放器保持暂停，恢复后才播放；过期播放器回调不会修改新请求状态。
- 内存警告停止声音，并排队释放模型与缓存；下一次请求重新初始化。
- 设置提供中英文试听、显式系统声音对比、合成时间及开源许可。

## 2026-10-10 验证

- 用户先前反馈 iPad 真机主要业务流程基本可用。
- iPad Pro 11-inch (M4)，设备名称「小米Pad」：6 项专项测试通过。覆盖真实中英文单词、句子、数字日期混合文本、速度变化、重听缓存、取消后继续合成、暂停与快速替换播放。
- iPadOS 27 模拟器：33 项单元测试、4 项 UI 测试通过。设置中的中英文试听、引擎切换与持久化，以及导入、OCR、旋转、主题、阅读恢复回归通过。
- iOS Release 无签名编译通过；真机 Debug 已签名安装并运行。当前真机 Debug 应用约 292 MB（包含测试 bundle），无签名 Release 应用约 246 MB（目录大小，未压缩；不等同于 IPA 下载大小）。
- 准备脚本的缓存安装成功；工程生成器在临时目录验证保留本机 Team 选择和模型／Swift 包引用。

真机 Debug 测试结果（速度 0.8，串行调用；英文单词包含首次模型初始化，其余为已初始化但音频缓存未命中）：

| 内容 | 合成时间 | 生成音频时长 | 重听缓存读取 |
| --- | ---: | ---: | ---: |
| squirrel | 1.52 秒 | 0.86 秒 | 0.59 毫秒 |
| 松鼠 | 0.60 秒 | 0.81 秒 | 0.61 毫秒 |
| The little squirrel lives in the forest. | 1.77 秒 | 2.46 秒 | 0.58 毫秒 |
| 小松鼠在森林里找到了一个种子。 | 2.76 秒 | 4.08 秒 | 0.64 毫秒 |
| 今天读 English，第 2 页。2026年10月10日。 | 4.32 秒 | 5.44 秒 | 0.65 毫秒 |

这些数字是原生合成耗时，不包含播放器启动、音频输出设备或用户点击耗时。缓存命中是读取已有音频，不代表端到端首播延迟。

测试进程在单词场景物理占用约 396–433 MiB；连续长句／混合文本测试最高观测物理占用约 919 MiB、累计 resident peak 约 1077 MiB。统计包含 app、XCTest、音频资源和运行库，不是单独模型大小；模型内部临时缓冲明显大于权重。M4 测试没有内存终止，但尚未证明低内存设备可以承受同样负载，长材料仍需要进一步测量／优化。

音频自动检查确认 24 kHz、有非静音且有限的 PCM、能由 AVAudioPlayer 解码、语速影响时长和播放状态正确。**不把这些检查等同于发音准确、自然或新安装飞行模式验收。** 真机生成的 WAV 已导出到本地 `artifacts/kokoro/`，供听读确认；原始指标在同目录 `device-metrics.txt`。

上游中文词典的罕见字「呣」带有词表未覆盖的 `❓` 发音标记，初始化日志会记录未知 token。常用样例通过波形测试，但罕见字、教材专名和长混合句仍需人工听读。

下一次设备验收：开启飞行模式并关闭 Wi-Fi，结束 App 后冷启动，分别试听中英文、点词／读整句／重听；如需验证首次安装无网络，先完成 Xcode 安装，再在首次打开前断网。记录可用性、音质和实际等待，避免把联网设备上的测试算作飞行模式通过。

## 来源与许可

- [Kokoro 1.1-zh 模型卡](https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh)：Apache 2.0。
- [sherpa-onnx 模型说明](https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html)及[固定运行库版本](https://github.com/k2-fsa/sherpa-onnx/tree/v1.13.8)：Apache 2.0。
- [ONNX Runtime](https://github.com/microsoft/onnxruntime)：MIT；[iOS 编译包](https://github.com/csukuangfj/onnxruntime-libs/releases/tag/v1.28.1)。
- [eSpeak NG](https://github.com/espeak-ng/espeak-ng/blob/master/COPYING)：GPLv3 或更新版本。[上游 iOS 构建脚本](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/build-ios.sh)明确合入 `libespeak-ng.a`，不是只有 Apache 的模型权重。
- [piper-phonemize](https://github.com/rhasspy/piper-phonemize)：MIT；[cppjieba](https://github.com/yanyiwu/cppjieba)：MIT。

对应许可全文随应用打包，在「设置 → 开源组件与许可」可查看；原模型包的许可和来源文件保持在模型资源内。本次为开发／真机验证集成，正式公开分发前仍需确定包含 GPLv3 发音组件的分发许可方案；当前没有替用户决定 SenLearn 的项目许可证。
