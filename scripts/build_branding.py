#!/usr/bin/env python3
"""里格账 / LigyTally 品牌资产生成器。

标记与中文标准字均为纯几何矢量路径，不依赖任何系统字体。
"""

import shutil
import subprocess
import tempfile
from pathlib import Path

OUT = Path("/Users/lotsohe/Desktop/LigyTally/assets/branding")
ANDROID_RES = Path(
    "/Users/lotsohe/Desktop/LigyTally/android/app/src/main/res"
)

BLUE = "#5190F2"
INK = "#17211E"
WHITE = "#FFFFFF"

# ── 标记 ──────────────────────────────────────────────────────────────
# 512 网格。单笔连续 L+G 合字。
# 笔画 40u，路径外框 288×288u，含描边视觉外框 328×328u。
# 最窄内隙 100u = 30.5%；G 开口 108u = 33%；内舌:底横 = 1:2。
MARK_PATH = "M400 112H112V400H400V260H256"
MARK_SW = 40
MARK_SW_REVERSED = 37   # 反白光学补偿：白色在深底上膨胀，减重 3u
MARK_RAW = 288          # 路径中线外框
MARK_VIS = 328          # 含描边视觉外框
MARK_ORIGIN = 92        # 视觉左上角在 512 网格中的坐标 (112 - 40/2)

# ── 中文标准字 ────────────────────────────────────────────────────────
# 每字设计框 100u，笔画 11u，方头端点、直角接合，与标记同一套骨架。
GLYPH_SW = 9
GLYPH_BOX = 100
GLYPH_PITCH = 118

GLYPHS = {
    # 田 + 土，中竖贯通共用
    "里": [
        "M24 8H76V54H24Z",
        "M24 31H76",
        "M50 8V92",
        "M32 71H68",
        "M12 92H88",
    ],
    # 木字旁 + 各（夂 + 口）
    "格": [
        "M4 38H44",
        "M24 8V92",
        "M24 54L8 86",
        "M25 52L40 68",
        "M74 8L58 28",
        "M50 30H92L62 58",
        "M70 42L94 62",
        "M56 64H92V92H56Z",
    ],
    # 贝字旁 + 长（竖提规整为水平短横，与标记方头直角同源）
    "账": [
        "M10 12H40V52H10Z",
        "M10 32H40",
        "M17 52L7 86",
        "M33 52L43 84",
        "M74 6L60 28",
        "M48 32H98",
        "M60 32V66",
        "M60 66H72",
        "M74 48L98 90",
    ],
}

WORDMARK = "里格账"
WORDMARK_RAW_W = GLYPH_PITCH * (len(WORDMARK) - 1) + GLYPH_BOX  # 332


DARK_BGS = {BLUE, INK}


def sw_for(bg):
    """深底反白时用光学补偿笔重。"""
    return MARK_SW_REVERSED if bg in DARK_BGS else MARK_SW


def mark(color, scale, tx, ty, sw=MARK_SW):
    """标记。tx/ty 为视觉外框左上角目标坐标。"""
    off_x = tx - MARK_ORIGIN * scale
    off_y = ty - MARK_ORIGIN * scale
    return (
        f'<g transform="translate({off_x:.3f} {off_y:.3f}) scale({scale:.6f})">'
        f'<path d="{MARK_PATH}" fill="none" stroke="{color}" stroke-width="{sw}"'
        f' stroke-linecap="square" stroke-linejoin="miter"/></g>'
    )


def wordmark(color, scale, tx, ty, sw=GLYPH_SW):
    """中文标准字「里格账」。tx/ty 为设计框左上角目标坐标。"""
    parts = [f'<g transform="translate({tx:.3f} {ty:.3f}) scale({scale:.6f})">']
    for i, ch in enumerate(WORDMARK):
        dx = i * GLYPH_PITCH
        parts.append(f'<g transform="translate({dx} 0)">')
        for d in GLYPHS[ch]:
            parts.append(
                f'<path d="{d}" fill="none" stroke="{color}"'
                f' stroke-width="{sw}" stroke-linecap="square"'
                f' stroke-linejoin="miter"/>'
            )
        parts.append("</g>")
    parts.append("</g>")
    return "".join(parts)


def svg(w, h, body, bg=None):
    head = (
        f'<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" fill="none"'
        f' xmlns="http://www.w3.org/2000/svg">'
    )
    rect = f'<rect width="{w}" height="{h}" fill="{bg}"/>' if bg else ""
    return f"{head}\n  {rect}\n  {body}\n</svg>\n"


# ── 横版锁定组合 ──────────────────────────────────────────────────────
LOCKUP_W, LOCKUP_H = 900, 320
MARK_H = 200                      # 标记视觉高
GAP = 68                          # 标记与标准字间距 = 标记高 × 0.34
WM_H = 148                        # 标准字高 = 标记高 × 0.74
GLYPH_SW_REVERSED = 8.4           # 反白光学补偿


def lockup(bg, fg):
    reversed_ = bg in DARK_BGS
    m_scale = MARK_H / MARK_VIS
    w_scale = WM_H / GLYPH_BOX
    wm_w = WORDMARK_RAW_W * w_scale
    content = MARK_H + GAP + wm_w
    x0 = (LOCKUP_W - content) / 2
    my = (LOCKUP_H - MARK_H) / 2
    wy = (LOCKUP_H - WM_H) / 2
    body = mark(fg, m_scale, x0, my, sw_for(bg)) + wordmark(
        fg,
        w_scale,
        x0 + MARK_H + GAP,
        wy,
        GLYPH_SW_REVERSED if reversed_ else GLYPH_SW,
    )
    return svg(LOCKUP_W, LOCKUP_H, body, bg)


# ── 纯标记 ────────────────────────────────────────────────────────────
def mark_only(color, size=512, pad_ratio=0.09):
    pad = size * pad_ratio
    vis = size - pad * 2
    return svg(size, size, mark(color, vis / MARK_VIS, pad, pad))


# ── App 图标（全出血，不自绘圆角）────────────────────────────────────
def app_icon(bg, fg, size=1024, mark_ratio=0.56):
    vis = size * mark_ratio
    off = (size - vis) / 2
    return svg(size, size, mark(fg, vis / MARK_VIS, off, off, sw_for(bg)), bg)


# ── 安卓自适应图标前景（安全区 66/108）──────────────────────────────
def adaptive_fg(fg, size=432):
    vis = size * 0.40
    off = (size - vis) / 2
    sw = MARK_SW_REVERSED if fg == WHITE else MARK_SW
    return svg(size, size, mark(fg, vis / MARK_VIS, off, off, sw))


VARIANTS = {
    # 名称: (背景, 前景)
    "on-blue": (BLUE, WHITE),   # 蓝底白字
    "on-dark": (INK, WHITE),    # 黑底白字
    "light": (WHITE, INK),      # 白底黑字
    "primary": (WHITE, BLUE),   # 白底蓝字
}

# 用户可切换的四款 App 图标。
# key 与 lib/core/preferences/app_icon.dart 的 AppIconStyle 一一对应，
# 也决定 assets/branding/app-icon-<key>.png 与安卓 mipmap 后缀。
APP_ICON_STYLES = {
    "dark": (INK, WHITE),       # 默认。旧版 AppIconStyle.dark 天然沿用
    "blue": (BLUE, WHITE),
    "light": (WHITE, INK),      # 旧版 AppIconStyle.light 天然沿用
    "tint": (WHITE, BLUE),
}

# 自适应图标前景按颜色复用，避免为同色前景生成两份相同位图。
FG_RES_BY_COLOR = {
    WHITE: "ic_launcher_foreground",
    INK: "ic_launcher_light_foreground",
    BLUE: "ic_launcher_tint_foreground",
}

# 安卓 launcher 各密度尺寸
MIPMAP = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
# 自适应图标前景各密度尺寸（108dp 基准）
MIPMAP_FG = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}


def system_sheet():
    """品牌系统总览：四版锁定组合 + App 图标 + 缩放序列。"""
    W, ROW = 1400, 300
    H = ROW * 4 + 420
    parts = []
    order = ["on-blue", "on-dark", "light", "primary"]
    for i, key in enumerate(order):
        bg, fg = VARIANTS[key]
        reversed_ = bg in DARK_BGS
        y = i * ROW
        parts.append(f'<rect y="{y}" width="{W}" height="{ROW}" fill="{bg}"/>')
        m_h = 150
        wm_h = 111
        w_scale = wm_h / GLYPH_BOX
        my = y + (ROW - m_h) / 2
        wy = y + (ROW - wm_h) / 2
        parts.append(mark(fg, m_h / MARK_VIS, 96, my, sw_for(bg)))
        parts.append(
            wordmark(
                fg,
                w_scale,
                96 + m_h + 51,
                wy,
                GLYPH_SW_REVERSED if reversed_ else GLYPH_SW,
            )
        )

    # App 图标行
    y = ROW * 4
    parts.append(f'<rect y="{y}" width="{W}" height="420" fill="#F5F5F5"/>')
    for i, (bg, fg) in enumerate(((BLUE, WHITE), (INK, WHITE), (WHITE, BLUE))):
        x = 96 + i * 220
        iy = y + 60
        parts.append(
            f'<rect x="{x}" y="{iy}" width="180" height="180" rx="40" fill="{bg}"/>'
        )
        if bg == WHITE:
            parts.append(
                f'<rect x="{x}" y="{iy}" width="180" height="180" rx="40"'
                f' fill="none" stroke="#DCDCDC" stroke-width="2"/>'
            )
        vis = 180 * 0.56
        off = (180 - vis) / 2
        parts.append(mark(fg, vis / MARK_VIS, x + off, iy + off, sw_for(bg)))

    # 缩放序列
    for i, px in enumerate((96, 64, 44, 28, 18)):
        x = 800 + i * 120
        cy = y + 150 - px / 2
        parts.append(
            f'<rect x="{x}" y="{cy}" width="{px}" height="{px}"'
            f' rx="{px * 0.22:.1f}" fill="{BLUE}"/>'
        )
        vis = px * 0.56
        off = (px - vis) / 2
        parts.append(
            mark(WHITE, vis / MARK_VIS, x + off, cy + off, MARK_SW_REVERSED)
        )

    return svg(W, H, "".join(parts))


def _rsvg():
    """定位 rsvg-convert。

    PATH 里找不到时兜一遍常见的 Homebrew 安装位置 —— 某些受限 shell
    （如编辑器内置终端）不会带上 /opt/homebrew/bin。
    """
    exe = shutil.which("rsvg-convert")
    if exe:
        return exe
    for p in ("/opt/homebrew/bin/rsvg-convert", "/usr/local/bin/rsvg-convert"):
        if Path(p).exists():
            return p
    return None


def rasterize(svg_path, png_path, width):
    """用 rsvg-convert 光栅化。缺少该工具时跳过并提示。"""
    exe = _rsvg()
    if not exe:
        return False
    subprocess.run(
        [exe, "-w", str(width), str(svg_path), "-o", str(png_path)],
        check=True,
    )
    return True


def build_android():
    """生成安卓 launcher 图标：4 套自适应 + legacy，各 5 档密度。

    四款图标对应 AppIconStyle 的四个 key（dark/blue/light/tint）。
    `ic_launcher` 无后缀，是 application 级默认，必须存在。
    """
    if not _rsvg():
        return []
    tmp = Path(tempfile.mkdtemp())
    done = []

    # 自适应前景。四款图标只用到三种前景色，白色前景由 dark 与 blue 共用。
    for fg, suffix in FG_RES_BY_COLOR.items():
        src = tmp / f"{suffix}.svg"
        src.write_text(adaptive_fg(fg))
        for density, size in MIPMAP_FG.items():
            out = ANDROID_RES / f"mipmap-{density}" / f"{suffix}.png"
            rasterize(src, out, size)
            done.append(out)

    # legacy 图标（Android 8 以下与部分 launcher 回退用）。
    # dark 落在无后缀的 ic_launcher 上 —— 它同时是 application 级默认图标。
    for key, (bg, fg) in APP_ICON_STYLES.items():
        suffix = "ic_launcher" if key == "dark" else f"ic_launcher_{key}"
        src = tmp / f"{suffix}.svg"
        src.write_text(app_icon(bg, fg, size=512))
        for density, size in MIPMAP.items():
            out = ANDROID_RES / f"mipmap-{density}" / f"{suffix}.png"
            rasterize(src, out, size)
            done.append(out)

    # 自适应图标描述文件。background 走 color 资源，foreground 走 mipmap。
    # 前景按颜色复用：白色前景由 dark 与 blue 共用。
    for key, (_, fg) in APP_ICON_STYLES.items():
        name = "ic_launcher" if key == "dark" else f"ic_launcher_{key}"
        bg_res = f"{name}_background"
        fg_res = FG_RES_BY_COLOR[fg]
        out = ANDROID_RES / "mipmap-anydpi-v26" / f"{name}.xml"
        out.write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            f'    <background android:drawable="@color/{bg_res}"/>\n'
            f'    <foreground android:drawable="@mipmap/{fg_res}"/>\n'
            f'    <monochrome android:drawable="@mipmap/{fg_res}"/>\n'
            "</adaptive-icon>\n"
        )
        done.append(out)

    # 自适应图标背景色（沿用项目既有的 ic_launcher_colors.xml，勿另建文件）
    lines = ['<?xml version="1.0" encoding="utf-8"?>', "<resources>"]
    for key, (bg, _) in APP_ICON_STYLES.items():
        name = "ic_launcher" if key == "dark" else f"ic_launcher_{key}"
        lines.append(f'    <color name="{name}_background">{bg}</color>')
    lines.append("</resources>")
    (ANDROID_RES / "values" / "ic_launcher_colors.xml").write_text(
        "\n".join(lines) + "\n"
    )
    shutil.rmtree(tmp)
    return done


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    svgs = []          # (path, png 宽度)

    for name, (bg, fg) in VARIANTS.items():
        p = OUT / f"ligytally-logo-{name}.svg"
        p.write_text(lockup(bg, fg))
        svgs.append((p, 1800))

    for name, color in (("", INK), ("-blue", BLUE), ("-white", WHITE)):
        p = OUT / f"ligytally-mark{name}.svg"
        p.write_text(mark_only(color))
        svgs.append((p, 1024))

    # App 图标。1024 全出血用于商店与设计交付。
    p = OUT / "ligytally-app-icon.svg"
    p.write_text(app_icon(BLUE, WHITE))
    svgs.append((p, 1024))

    # 应用内「图标切换」预览图，512。
    # 文件名与 AppIconStyle 的 key 一一对应，被 lib/features/settings 引用，勿改名。
    for key, (bg, fg) in APP_ICON_STYLES.items():
        p = OUT / f"app-icon-{key}.svg"
        p.write_text(app_icon(bg, fg, size=512))
        svgs.append((p, 512))

    p = OUT / "ligytally-system.svg"
    p.write_text(system_sheet())
    svgs.append((p, 1400))

    ok = True
    for path, w in svgs:
        if not rasterize(path, path.with_suffix(".png"), w):
            ok = False
            break
        print(f"{path.name}  +  {path.stem}.png")

    if not ok:
        print("rsvg-convert 未安装，仅生成 SVG。brew install librsvg 后重跑可出 PNG。")
    else:
        android = build_android()
        print(f"android launcher icons: {len(android)} 个")
