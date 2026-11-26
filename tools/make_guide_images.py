from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / 'prototype' / 'shots'
OUT = ROOT / 'docs' / 'images'
FONT_PATH = '/System/Library/Fonts/Hiragino Sans GB.ttc'

PHONE_W = 820
PHONE_H = 1728
PAD = 14
COLS = (92, 940, 1788)
ROWS = {
    'records': (131, 2149, 4207, 6224),
    'doulist': (131,),
    'plan': (131, 2149),
    'report': (131,),
    'settings': (131, 2189, 4207),
}

BG_TOP = (251, 247, 239)
BG_BOTTOM = (234, 229, 219)
TEXT = (33, 30, 24)
TEXT2 = (94, 87, 74)
MUTED = (139, 130, 115)
GOLD = (154, 98, 17)
GOLD_BRIGHT = (232, 182, 92)
CARD = (255, 252, 246)
BORDER = (217, 207, 190)

JOBS = [
    ('guide-records.png', '记录 · 一屏浏览书影', '按生效日期分组，观影 / 读书与已看 / 想看同页切换。', [
        ('records', 0, 0, '已看 / 想看'),
        ('records', 0, 1, '读书记录'),
        ('records', 0, 2, '想看 / 待映'),
    ]),
    ('guide-record-detail.png', '详情 · 把感受留在本地', '详情、编辑与补录都用半屏浮层，关闭后保留列表位置。', [
        ('records', 2, 0, '记录详情'),
        ('records', 2, 1, '编辑记录'),
        ('records', 2, 2, '手动补录'),
    ]),
    ('guide-sync.png', '同步豆瓣 · 一次同步全部收藏', '观影、读书、想看 / 想读与豆列分别勾选；本地修改不会被覆盖。', [
        ('records', 3, 0, '选择同步范围'),
        ('records', 3, 1, '扫码登录'),
    ]),
    ('guide-doulist.png', '豆列 · 整理片单与书单', '片单书单集中管理，条目可补时长、页数与字数。', [
        ('doulist', 0, 0, '我的豆列'),
        ('doulist', 0, 1, '豆列详情'),
        ('doulist', 0, 2, '条目信息'),
    ]),
    ('guide-plan.png', '计划 · 从想看到完成', '想看的作品放进计划文件夹，按顺序推进并导出 PNG。', [
        ('plan', 0, 0, '计划列表'),
        ('plan', 0, 1, '计划详情'),
        ('plan', 0, 2, '从想看添加'),
    ]),
    ('guide-report.png', '报告 · 月报与年报', '复用桌面报告版式，月报 / 年报 / 自定义范围都能预览分享。', [
        ('report', 0, 0, '报告中心'),
        ('report', 0, 1, '报告预览'),
        ('report', 0, 2, '批量生成'),
    ]),
    ('guide-settings.png', '设置 · 数据与备份', 'Excel、云同步、字数统计与回收站，数据入口都收在设置里。', [
        ('settings', 0, 0, '应用设置'),
        ('settings', 1, 1, '选择同步版本'),
        ('settings', 1, 2, '字数统计'),
    ]),
    ('guide-explore.png', '探索空间 · 资源站点', '远端配置加本地站点，详情页按标题直达搜索，不注入 Cookie。', [
        ('settings', 0, 1, '探索空间'),
        ('settings', 0, 2, '新增本地站点'),
        ('records', 1, 0, '详情页资源'),
    ]),
]


def font(size):
    return ImageFont.truetype(FONT_PATH, size, index=0)


def background(width, height):
    image = Image.new('RGB', (width, height), BG_BOTTOM)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / max(1, height - 1)
        color = tuple(round(BG_TOP[i] * (1 - t) + BG_BOTTOM[i] * t) for i in range(3))
        draw.line((0, y, width, y), fill=color)
    return image


def phone(group, row, col):
    image = Image.open(SHOTS / f'{group}.png').convert('RGB')
    left = COLS[col] - PAD
    top = ROWS[group][row] - PAD
    box = (left, top, left + PHONE_W + PAD * 2, top + PHONE_H + PAD * 2)
    return image.crop(box)


def rounded_rect(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def build(job):
    filename, title, subtitle, screens = job
    count = len(screens)
    gap = 64
    margin = 82
    header_h = 234
    footer_h = 110
    phone_h = PHONE_H + PAD * 2
    width = margin * 2 + count * (PHONE_W + PAD * 2) + (count - 1) * gap
    height = header_h + phone_h + footer_h
    image = background(width, height)
    draw = ImageDraw.Draw(image)

    draw.rectangle((margin, 34, margin + 44, 40), fill=GOLD_BRIGHT)
    draw.text((margin, 58), '书影记录 · iOS', font=font(24), fill=GOLD)
    draw.text((margin, 96), title, font=font(54), fill=TEXT)
    draw.text((margin, 168), subtitle, font=font(25), fill=TEXT2)

    number = JOBS.index(job) + 1
    label = f'{number:02d} / {len(JOBS):02d}'
    label_font = font(22)
    draw.text((width - margin - label_font.getlength(label), 62), label,
              font=label_font, fill=MUTED)

    x = margin
    for index, (group, row, col, _) in enumerate(screens):
        tile = phone(group, row, col).convert('RGBA')
        mask = Image.new('L', tile.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, tile.width, tile.height), radius=46, fill=255)
        shadow = Image.new('RGBA', image.size, (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle(
            (x + 8, header_h + 12, x + tile.width + 8, header_h + tile.height + 12),
            radius=46, fill=(28, 22, 12, 95))
        image = Image.alpha_composite(image.convert('RGBA'),
                                      shadow.filter(ImageFilter.GaussianBlur(18))).convert('RGB')
        image.paste(tile, (x, header_h), mask)
        caption = screens[index][3]
        badge_x = x + PHONE_W // 2 - 96
        badge_y = header_h + phone_h + 20
        draw = ImageDraw.Draw(image)
        draw.ellipse((badge_x, badge_y, badge_x + 34, badge_y + 34), fill=GOLD_BRIGHT)
        badge_font = font(19)
        draw.text((badge_x + 17, badge_y + 17), str(index + 1), font=badge_font,
                  fill=(33, 27, 16), anchor='mm')
        draw.text((badge_x + 46, badge_y + 8), caption, font=font(24), fill=TEXT2)
        x += PHONE_W + PAD * 2 + gap

    OUT.mkdir(parents=True, exist_ok=True)
    scale = 1800 / width
    image = image.resize((round(width * scale), round(height * scale)), Image.Resampling.LANCZOS)
    image.save(OUT / filename, optimize=True)
    print('wrote', OUT / filename)


def main():
    for job in JOBS:
        build(job)
    icon = Image.open(ROOT / 'BookFilmJournal-iOS' / 'Assets.xcassets' / 'AppIcon.appiconset' / 'AppIcon-1024.png').convert('RGBA')
    mask = Image.new('L', icon.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, icon.width, icon.height), radius=220, fill=255)
    icon.putalpha(mask)
    icon.save(OUT / 'icon-rounded.png', optimize=True)
    print('wrote', OUT / 'icon-rounded.png')


if __name__ == '__main__':
    main()
