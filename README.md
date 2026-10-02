# 虎整辅助补丁

基于官方虎整句 D89-r3，补充小鹤反查、快符、统计、拆分和 Emoji。
官方核心、码表和模型继续单独安装；这个仓库保存 19 个辅助资源。

当前行为：拆分只在小鹤反查时显示；Emoji 始终开启。
key_binder 保持在虎整核心之后，官方基础绑定沿用原方案。
个人快捷键和中英切换设置继续由 chezmoi 管理。

## 恢复安装

先安装官方虎整句，再恢复 chezmoi 中的个人 custom。在仓库目录运行：

```sh
python scripts/install.py --rime-dir ~/.local/share/fcitx5/rime --dry-run
python scripts/install.py --rime-dir ~/.local/share/fcitx5/rime
python scripts/install.py --rime-dir ~/.local/share/fcitx5/rime --check
rime_deployer --build ~/.local/share/fcitx5/rime /usr/share/rime-data ~/.local/share/fcitx5/rime/build
```

安装脚本只管理 manifest.json 中列出的辅助文件。替换已有辅助文件前会备份到
Rime 的 backups/tiger-addons-时间/，相同文件跳过。
个人 custom、官方核心、全局 symbols.yaml、学习记录和统计数据保持不变。
部署后重载桌面输入法。当前机器可以使用：

```sh
systemctl --user restart app-org.fcitx.Fcitx5@autostart.service
```

没有现成 custom 时，可以使用 config/tiger_sentence.custom.yaml 中的辅助模板；
已有 custom 时，合并模板的 patch 条目，保留原有设置。
模板不包含个人快捷键；个人绑定继续使用 key_binder/bindings/+。

## 验证

验证需要 Python/PyYAML、g++、librime 开发头文件、librime-lua 和 rime_deployer。
在 Arch 上对应 python-yaml、gcc、librime、当前使用的 librime-lua 包和 librime 工具。

```sh
python scripts/verify.py --base-rime-dir ~/.local/share/fcitx5/rime
python tests/install_smoke.py
```

脚本从官方源码和本仓库资源创建临时 Rime 目录，并从零部署。
模型通过只读访问复用，学习数据库和统计数据库使用新的临时数据。
检查覆盖小鹤反查、自动拆分、常开 Emoji、Tab/Shift+Tab、Ctrl+n/p、
快符、弱纠错、提前上屏与统计。日志保留在脚本打印的临时目录。
测试夹具只设置 Ctrl+n/p 翻页，不包含个人 custom。

## 跟进官方更新

BASELINE.json 记录当前基线和源包校验值。先单独升级官方方案，再运行验证。
验证其他版本时显式加 --allow-new-base；通过后更新基线和兼容记录。
辅助文件发生变化时，需要同步更新 manifest.json 中的 SHA-256。

[功能用法与快符限制](docs/usage.md) · [资源来源和本地修改](SOURCES.md)

仓库不包含模型、build 产物、学习数据库、统计数据和私人配置。
