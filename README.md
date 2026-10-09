# 虎整辅助补丁

基于官方虎整句 1.6.20261009（4eaf42e），补充小鹤反查、统计、拆分、Emoji 和独立个人词库。
官方核心、码表和模型继续单独安装；这个仓库保存 16 个辅助资源，并提供一处个人词库加载补丁。

当前行为：拆分只在小鹤反查时显示；Emoji 始终开启。
标点沿用官方映射；统计从方案菜单打开，不占用标点键。
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

安装脚本管理 manifest.json 中列出的辅助文件，并应用个人词库加载补丁。替换已有辅助文件前会备份到
Rime 的 backups/tiger-addons-时间/，相同文件跳过。
清单 retired 中的旧辅助文件也会先备份再移除，包含已经停用的快符、符号轮换和扩展符号表。
安装时也会备份并修改 lua/tiger_sentence.lua 的词库加载与字符最优码判断。
这处补丁可以重复应用；无法识别的核心代码会在写入前报错。
个人 custom、个人词库、官方码表、全局 symbols.yaml、学习记录和统计数据保持不变。
部署后重载桌面输入法。当前机器可以使用：

```sh
systemctl --user restart app-org.fcitx.Fcitx5@autostart.service
```

没有现成 custom 时，可以使用 config/tiger_sentence.custom.yaml 中的辅助模板；
已有 custom 时，合并模板的 patch 条目，保留原有设置。
模板不包含个人快捷键；个人绑定继续使用 key_binder/bindings/+。

## 修改后安装

修改 assets/ 下的源码或数据后，在仓库目录运行：

```sh
python scripts/refresh_manifest.py
python scripts/verify.py --base-rime-dir ~/.local/share/fcitx5/rime
python scripts/install.py --rime-dir ~/.local/share/fcitx5/rime
rime_deployer --build ~/.local/share/fcitx5/rime /usr/share/rime-data ~/.local/share/fcitx5/rime/build
systemctl --user restart app-org.fcitx.Fcitx5@autostart.service
```

refresh_manifest.py 只更新已登记资源的哈希；新增辅助文件时，先在 manifest.json
的 assets 列表加入路径和 sha256 字段，再运行它。修改源码与清单一起提交。
config/ 下的 custom 是辅助模板，安装脚本不会覆盖正在使用的 custom；
涉及配置条目调整时，同步修改 chezmoi 管理的个人 custom 并应用。

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
普通标点、弱纠错、提前上屏与统计。个人词库测试覆盖前置/后置、整句组词、
分号选重、标点，以及全部原字符的最优码和候选保留。日志保留在脚本打印的临时目录。
测试夹具只设置 Ctrl+n/p 翻页，不包含个人 custom。

## 跟进官方更新

BASELINE.json 记录当前基线和源包校验值。先单独升级官方方案，再运行安装脚本恢复
个人词库补丁，随后验证。验证基线时会剥离本仓库的核心补丁，再核对官方源文件哈希。
验证其他版本时显式加 --allow-new-base；通过后更新基线和兼容记录。
辅助文件发生变化时，运行 scripts/refresh_manifest.py 更新 manifest.json 中的 SHA-256。

[功能用法与标点说明](docs/usage.md) · [资源来源和本地修改](SOURCES.md)

仓库不包含模型、完整官方核心、build 产物、学习数据库、统计数据和私人词库。
