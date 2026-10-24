# 轨迹控制面板

- [手动验收](验收.md)：界面与手机上的操作步骤。
- [设备会话](../Backend/session.py)：固定定位、路线与暂停恢复。
- [位置传输](../Backend/connection.py)：USB 连接及定位写入。
- [路线和配速](../Backend/engine.py)。
- [协议定义](../Backend/models.py) → [Swift 类型生成器](../Backend/generate_protocol.py)。
- [地图坐标边界与探索地图配置](../LocationController/MapCoordinate.swift)。
- [地图点选与地点搜索](../LocationController/MapPointPicker.swift)。
- [GPX 文档与扰动](../LocationController/GPXDocument.swift) → [编辑状态与历史](../LocationController/GPXEditorModel.swift)。
- [GPX 编辑界面](../LocationController/GPXEditor.swift) → [路线地图](../LocationController/GPXRouteMap.swift)。
- [GPX 定向验证入口](../Scripts/check-gpx.zsh)：文档往返、编辑历史、扰动和会话协议；不连接设备。
- [应用构建入口](../Scripts/build.zsh)。
- [打包入口](../Scripts/package.py)。
- [交付包检查](../Scripts/check-package.py)：不连接设备的签名与协议检查。
- [第三方依赖](../第三方项目说明.md)。

应用包为 Apple Silicon 架构，最低 macOS 13；包含独立设备后端。地图显示与地点搜索需要网络。iOS 27 USB 方式不需要启动 LocationSimulator。

执行构建需要项目独立 Python 环境；缺失时先运行 `zsh Backend/setup.zsh`，再运行 `zsh Scripts/build.zsh`。
构建产物位于 `dist/轨迹控制面板.app`。按需运行对应测试文件，不执行全量测试。
