# 中亿联达 · 智能打托

Flutter iPhone 应用，离线计算矩形箱在托盘上的规则码垛方案，预览单层布局并保存本机方案。

## 功能

- 箱体长、宽、高和单箱重量；托盘尺寸、自身高度、含托盘总限高、货物限载。
- 支持箱间间隙、托盘留边，以及 1200×1000、1200×800、1100×1100 mm 预设。
- 比较水平旋转及混合行列布局；输出每层箱位、总箱数、层数、货物重量、总高和首层利用率。
- 本机方案保存、载入、删除；无需账号或网络。

这是从零开发的离线规划版本，不连接 PLC 或打托设备。算法是规则行列排布启发式，不保证全局最优，不分析纸箱承压、重心、摩擦或运输稳定性。现场使用前须核验方案。

## 开发

Flutter 版本见 `.github/workflows/ios-release.yml`（与验证版本固定一致）。

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run
```

尺寸使用 mm，重量使用 kg；箱体保持直立，仅在平面旋转 90°。载重不含托盘重量。末层允许不足一整层，需现场确认稳定性。方案使用设备本地存储，卸载应用会删除数据。

## iOS Release 与 IPA

推送到 `main` 或手动运行 GitHub Actions 的 **iOS Release (unsigned IPA)** 工作流，会在 macOS 上执行测试及：

```sh
flutter build ios --release --no-codesign
```

工作流将实际的 `Runner.app` 打包为 `Payload/Runner.app`，验证 arm64 Mach-O 可执行文件和 Flutter AOT 框架后，上传 `ZhongyiLianda-unsigned.ipa` 与 SHA256 校验文件。构建成功后还会创建预发布 Release 以提供直接下载地址。

**这是未签名的真实 iOS Release IPA。普通 iPhone 安装运行仍需要有效签名。** 不需要将证书、密码或任何 Apple 密钥提交到本仓库。此构建不等于 TestFlight 或 App Store 发布。

## 项目结构

- `lib/main.dart`：中文界面、参数编辑、布局绘制和本机方案库。
- `lib/domain/packing.dart`：纯 Dart 排布计算与输入校验。
- `test/`：布局几何约束、边界条件和应用交互测试。
- `ios/`：完整 Xcode 工程与应用图标。
- `.github/workflows/ios-release.yml`：macOS 未签名 Release 编译及下载产物。

隐私：应用没有业务服务器、账户或分析 SDK；不请求相机、定位、通讯录等权限。
