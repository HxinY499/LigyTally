# 里格账 品牌规范

「里格账」＝「理个账」。标记是 **L + G 单笔合字** —— 对应英文名 **L**igy / **T**ally 与中文「**里格**」拼音首字母，双层落点。

内伸的那一横不是 G 的装饰，是账页上划下的**结算线**：「理」完之后落下的一笔。

## 标记几何

512 网格，纯路径描边，无填充。

```
d            M400 112H112V400H400V260H256
stroke-width 40（亮底） / 37（深底反白光学补偿）
linecap      square
linejoin     miter
```

| 参数 | 值 | 说明 |
|---|---|---|
| 视觉外框 | 328 × 328u | 含描边，严格正方 |
| 路径中线框 | 288 × 288u | |
| 笔画 | 40u | 占外框 12.2% |
| 最窄内隙 | 100u ＝ **30.5%** | 决定小尺寸可辨识度的关键指标 |
| G 开口 | 108u ＝ 33% | |
| 内舌 : 底横 | 1 : 2 | 结算线须读出对底横的从属关系 |

**内隙 30.5% 是硬指标，不许压低。** 24px 通知栏尺寸下有效内隙 7.6px；低于 25% 会在栅格化后糊成实心块。

## 中文标准字

「里格账」为纯几何路径，**不依赖任何系统字体**，与标记同一套骨架：全直线、方头端点、直角接合。

| 参数 | 值 |
|---|---|
| 设计框 | 100 × 100u |
| 字距 | 118u |
| 笔画 | 9u（亮底） / 8.4u（深底反白） |
| 整体宽 | 336u |

「长」的竖提规整为**水平短横** —— 斜提在纯直线约束下与撇捺打结，短横同时消掉尖角毛刺。

## 色彩

| 角色 | 值 | 来源 |
|---|---|---|
| 主色 | `#5190F2` | `lib/core/theme/app_accent.dart` blue |
| 墨色 | `#17211E` | `app_theme.dart` ink |
| 白 | `#FFFFFF` | |

不新造色。全部取自产品既有 token，让 logo 与界面属于同一套视觉系统。

## 四版组合

横版锁定组合 900 × 320，标记高 200u，间距 68u（＝标记高 × 0.34），标准字高 148u（＝标记高 × 0.74）。

| 文件 | 配色 | 用途 |
|---|---|---|
| `ligytally-logo-on-blue` | 蓝底白字 | 主用。品牌主视觉、启动页、物料封面 |
| `ligytally-logo-on-dark` | 黑底白字 | 深色界面、深色物料 |
| `ligytally-logo-light` | 白底黑字 | 印刷单色、传真、盖章场景 |
| `ligytally-logo-primary` | 白底蓝字 | 亮色界面内嵌、文档页眉 |

**深底反白必须减重。** 白色在深底上会光学膨胀：标记 40u → 37u，标准字 9u → 8.4u。不做补偿会显著粗于亮底版。

## 留白与禁止事项

- 最小留白 ＝ 标记笔画宽（40u 换算到当前尺寸）
- 标记最小使用尺寸 **18px**；低于此改用纯色方块 + 单字
- 不许：改变内隙比例 · 加圆角 · 加渐变/投影 · 拆开合字 · 拉伸变形 · 换非规范色 · 在标记与标准字之间改变间距比例

## 资产清单

`assets/branding/` — 每个 SVG 均配同名 PNG

```
ligytally-logo-{on-blue,on-dark,light,primary}   横版锁定组合 900×320
ligytally-mark{,-blue,-white}                    纯标记 512×512
ligytally-app-icon                               App 图标 1024×1024 全出血
app-icon-{dark,blue,light,tint}                  应用内图标切换预览 512×512
ligytally-system                                 品牌系统总览
```

⚠️ `app-icon-*.png` 与 `ligytally-mark.png` 的文件名被 `lib/` 下五处 Dart 引用锁定，
**改名会导致运行时资源缺失**（`flutter analyze` 查不出来，只在运行时崩）。

App 图标为**全出血、不自绘圆角** —— 圆角交由各平台系统遮罩处理。标记占画布 56%。

## 四款可切换 App 图标

用户可在「设置 → 外观 → 应用图标」里切换。key 是三处资源的共同命名依据：

| key | 中文名 | 配色 | mipmap 后缀 | alias |
|---|---|---|---|---|
| `dark` | 墨黑 | 黑底白标 | *（无后缀）* | `.LauncherDark` |
| `blue` | 品牌蓝 | 蓝底白标 | `_blue` | `.LauncherBlue` |
| `light` | 素白 | 白底黑标 | `_light` | `.LauncherLight` |
| `tint` | 浅蓝 | 白底蓝标 | `_tint` | `.LauncherTint` |

`dark` 是默认值，落在无后缀的 `ic_launcher` 上 —— 它同时是 application 级默认图标，必须存在。
`dark` / `light` 沿用了早期版本的 key 原义，所以老用户的 SharedPreferences 值零迁移成本。

改这套需五处同步：`AppIconStyle` 枚举 · `pubspec.yaml` 声明 · `AndroidManifest.xml` alias ·
`MainActivity.kt` 的 `ICON_ALIASES` · `build_branding.py` 的 `APP_ICON_STYLES`。

### ⚠️ 新增图标时的两条硬约束

1. **manifest 里新 alias 必须 `enabled="false"`**，只有默认那个是 `true`。
   新 alias 若默认启用，老用户升级后桌面会同时冒出多个图标。
2. **切换时先启用目标、再禁用其余。** 反序会出现「全部禁用」的瞬时状态，
   某些 launcher 会把应用从桌面移除。

`android/app/src/main/res/` — 20 个 legacy launcher PNG（5 档密度 × 4 款）
+ 15 个自适应前景 PNG（5 档密度 × 3 种前景色，白色前景由 dark 与 blue 共用）
+ 4 个 `mipmap-anydpi-v26/*.xml`。
自适应前景标记占 40%，落在 66/108 安全区内；圆形 / 圆角方 / 全出血三种系统裁切均已验证无截断。
背景色在 `values/ic_launcher_colors.xml`。

## 重新生成

```bash
python3 scripts/build_branding.py
```

改几何只需改 `scripts/build_branding.py` 顶部常量与 `GLYPHS` 字典，全部资产会一并重算。依赖 `rsvg-convert`（`brew install librsvg`）出 PNG；缺失时只产 SVG。
