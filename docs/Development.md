# 首个开发里程碑

## 设计优先级

2026-10-10 用户明确：项目内 UI 图优先于网页原型，原型仅供参考。阅读界面围绕大幅原页、温暖纸色、克制工具栏与底部三个大按钮构建。四主题与阅读状态独立的交互规则继续沿用。

## 当前工程决策

- 首个工程采用 SwiftUI 界面，UIKit 提供原页缩放、命中测试与可访问词元素；最低 iOS / iPadOS 17。先交付原生能力闭环。概念稿提到的 Capacitor 暂未引入；后续若确定需要 Web 界面，再明确桥接职责，避免维护两套阅读界面。
- `MaterialImporter` actor 管理安全作用域文件、PDFKit 渲染和照片方向归一化，限制导入大小并在分页处理之间检查取消。页面以长边最多 2000 像素的 JPEG 保存；原 PDF 另存。
- `TextRecognizer` actor 使用 Vision accurate OCR 和真实字符范围词框，转换为左上原点归一化坐标。NaturalLanguage 负责词语和句子分割。此版本为横排阅读顺序，复杂排版待验证。
- `LibraryStore` 将书本元数据编码为 JSON 存进 SQLite 行；图片和原始 PDF 采用 UUID 文件名独立保存。数据库提交成功后才更新界面；失败时回滚新文件。读取损坏数据会停止写入并提示，不建立假空书架覆盖资料。
- `SpeechPlayer` 独立管理系统语音、语速、最新一次播放、暂停与音频中断。播放对象有身份检查，旧回调不能覆盖新一次点词状态。系统声音只是当前验证引擎，Kokoro 的模型打包、授权、体积、延迟和内存仍需专项集成验证。
- 进入页面时按需 OCR。主题只修改外观，离开阅读或翻页停止声音，重启恢复页码但不自动播放。恢复默认主题只修改主题。
- 校对保留原始识别结果；文字改变即移除该行活动词框，保留用于撤销的原始词框。校对行仍参与整页和文字列表朗读，不用旧几何伪装逐词对应。

## 接下来需要真机验证

1. 选择目标 iPad 与最低实际测试系统，运行相机连续扫描和追加页面。
2. 飞行模式下首次安装、冷启动和重启，分别播放中英文；验证当前系统声音与后续打包模型的差异。首次离线语音尚未达到产品验收承诺。
3. 用真实教材测试密集词框、倾斜拍摄、混合中英文、多栏、长 PDF，记录识别定位问题和内存峰值。
4. 记录点词到声音的首播/热播等待、切后台、快速连续点击、耳机拔出后的行为。
5. 验收 VoiceOver、大字体、横竖屏、分屏和四主题；检查教材颜色、选词、页码和正在播放的内容是否保持。
6. 补充图片旋转/裁切、可恢复后台识别队列和校对词框重建，再进入完整首版验收。

## 开发验证记录

2026-10-10，Apple Silicon Mac / Xcode 27：

- 23 项单元测试通过，包含真实中英文 Vision OCR、小尺寸 PDF 铺满渲染、图像方向、跨行句子、校对撤销与 SQLite 失败回滚。
- iPad Pro 13-inch (M5) / iPadOS 27 模拟器：示例导入、点词、整句、翻页、切换月光主题、重启页码与主题恢复、恢复默认主题、横竖屏和返回书架通过自动化操作。
- iPhone 18 Pro / iOS 27 模拟器：竖屏导入、点词、滚动设置并切换主题、选词与页码保持通过自动化操作。
- iOS Release 无签名编译通过。尚未连接实体 iPad，因此没有把模拟器结果写成真机验收通过。
- `.gitignore` 已实测排除 IDE 用户配置、构建、测试产物、环境文件和签名私钥。

## 第二阶段：导入进度

- PDF 和照片在每页转换完成后报告真实页数；照片选择器读取原始数据时单独显示读取进度。
- 进度回调切回主线程更新界面，处理前后检查取消；材料全部处理成功且未取消才进入书架事务。
- 新增处理完首张照片后取消的测试，确保不会继续处理或返回部分材料；PDF 测试同时验证进度从 0 到总页数顺序递增。
- 2026-10-10：24 项单元测试、2 项 iPad 界面回归通过；iOS Release 无签名编译通过。

## Apple 技术依据

- [Recognizing text in images](https://developer.apple.com/documentation/vision/recognizing-text-in-images)：Vision OCR 及文字范围定位。
- [Speech synthesis](https://developer.apple.com/documentation/avfoundation/speech-synthesis)：设备端语音合成。
- [speechVoices()](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice/speechvoices())：查询设备可提供的声音。
- [Required reason API](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)：当前隐私清单声明应用自身 UserDefaults 使用理由 `CA92.1`。
