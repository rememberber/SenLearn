# SenLearn · 森学

面向儿童学习与家长陪伴的本地 iOS / iPadOS 点读应用。当前版本是可运行的首个开发里程碑：真实材料导入、OCR 词框、系统语音点读和本地书架。

## 运行

1. 使用 Xcode 16 或更新版本打开 `SenLearn.xcodeproj`。
2. 选择 `SenLearn` scheme 和 iPad / iPhone 模拟器，运行。最低部署版本为 iOS / iPadOS 17。
3. 空书架选择「试读示例」，应用会生成两页原创示例 PDF，经过与用户材料相同的导入、识别流程，再点击文字试听。
4. 真机运行时，在 Signing & Capabilities 中选择自己的 Team，必要时改为唯一的 Bundle Identifier。仓库不包含个人签名配置。

项目仅依赖 Apple 系统框架与 SQLite，无需安装 npm、CocoaPods 或第三方 Swift 包。项目已包含 Xcode 工程，新增 Swift 文件会由同步目录自动纳入工程。如需重建工程配置，可运行 `python3 scripts/generate_project.py`。

```sh
xcodebuild -project SenLearn.xcodeproj -scheme SenLearn \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build

# 先用 xcrun simctl list devices available 查找本机模拟器名称
xcodebuild -project SenLearn.xcodeproj -scheme SenLearn \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

## 当前可用

- 书架：导入、继续阅读、重命名、确认移除；SQLite 保存书本、识别结果、校对文字与页码。
- 导入：PDF、本地图片、按选择顺序导入多张照片；支持通过家长辅助菜单向已有书追加页面。真机可调用系统多页文档扫描器。导入时显示照片读取及书页处理进度，支持取消；取消不会保存半本材料。
- OCR：Vision 本地中英文识别；进入页面时按需识别，保留真实词框；失败可以重试。不会将示例文字冒充真实识别结果。
- 点读：原页缩放、点词发音、跨行句子朗读、听整页、重听、暂停、停止与语速。相邻词命中存在歧义时显示候选词。
- 校对：对照原图修改识别行，支持恢复原始识别。改过文字的行暂时关闭逐词点读，以免使用错误位置；可在文字列表或整页朗读中听到校对后的文字。
- 书页整理：在「家长辅助 → 旋转书页」预览左右旋转，取消不改变书页；保存后重新识别，清除旧词框和本页校对文字，保留页码和原 PDF。保存失败时保留原书页。
- 外观：森间书桌、清透原生、探索乐园、月光共读；主题持久化，切换不重置页码、选词或语速。家长页目录、减少动态效果独立保存。

## 当前边界

- 语音使用设备提供的 `AVSpeechSynthesizer` 声音。**尚未集成 Kokoro / Qwen3-TTS，也尚未完成“新安装后首次断网即可中英发音”的真机验收。** 无可用声音时显示提示，不调用云端 TTS。
- 连续拍摄需要支持系统文档扫描的真机；模拟器关闭这一入口。相机权限、发音质量、音频中断和真实教材表现仍需设备测试。
- 一次导入最多 100 页 PDF、30 张照片、合计 100 MB。工作图像长边最多 2000 像素；PDF 原文件另存于本机，外部原文件不会修改。大 PDF 的导入目前需等全部页面生成工作图像后进入阅读，OCR 则逐页按需执行。
- 不支持加密 PDF。照片的手动裁切、选区重识别、校对后的词框重新映射、后台 OCR 队列尚未完成。
- 当前按横向排版从上到下、同行从左到右读取；复杂多栏、竖排、手写教材需要后续专项处理。
- 标注、词典释义、总结、动画生成、声音复刻等后续能力未提供入口。

## 设计与实现依据

**项目 UI 图优先于网页原型。** 以 `docs/ui-ux/01-forest.png` 的纸色、森林绿和原页主体为主，结合 `03-play.png` 的大触控操作。原型只参考交互行为，不照搬其布局。教材原色在所有主题下保持不变。

- [产品概念](docs/DesignConcept.md)
- [UI / UE 规则](docs/ui-ux/设计说明.md)
- [工程决策与后续验收](docs/Development.md)

`SenLearnTests` 覆盖 SQLite 重启恢复、追加顺序、事务失败回滚、损坏数据保护、真实 Vision OCR、图像方向、PDF 渲染和句子分割；`SenLearnUITests` 覆盖示例导入、点词、翻页、主题切换与重启恢复。测试生成的数据库和截图独立于用户资料。

`.gitignore` 已排除 `.idea/`、Xcode 用户状态、构建与测试产物、环境配置和签名文件；保留共享工程、源码和设计资料。
