"""生成《共生之缚》场景文档（Word）。

正文宋体、标题黑体、A4、白底黑字；不用表格，能写成句子的就写句子，条目用短横线列表。
图片来自 client/shots/doc/*.png（由 client/tests/doc_shots.gd 拍的实机画面）。
"""

from __future__ import annotations

import sys
from pathlib import Path

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.shared import Cm, Pt

ROOT = Path(__file__).resolve().parents[2]   # tools/report/ → 仓库根
SHOTS = ROOT / "client" / "shots" / "doc"
OUT = ROOT / "doc" / "共生之缚-场景文档.docx"

SONG = "宋体"
HEI = "黑体"


def style_font(style, name: str, size: float, bold: bool = False) -> None:
    style.font.name = name
    style.font.size = Pt(size)
    style.font.bold = bold
    style.font.color.rgb = None
    rpr = style.element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = rpr.makeelement(qn("w:rFonts"), {})
        rpr.append(rfonts)
    for tag in ("w:ascii", "w:hAnsi", "w:eastAsia"):
        rfonts.set(qn(tag), name)


def run_font(run, name: str) -> None:
    run.font.name = name
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = rpr.makeelement(qn("w:rFonts"), {})
        rpr.append(rfonts)
    for tag in ("w:ascii", "w:hAnsi", "w:eastAsia"):
        rfonts.set(qn(tag), name)


class Doc:
    def __init__(self) -> None:
        self.d = Document()
        self.pic = 0
        sec = self.d.sections[0]
        sec.page_width = Cm(21.0)
        sec.page_height = Cm(29.7)
        sec.left_margin = Cm(2.5)
        sec.right_margin = Cm(2.5)
        sec.top_margin = Cm(2.5)
        sec.bottom_margin = Cm(2.5)

        normal = self.d.styles["Normal"]
        style_font(normal, SONG, 10.5)
        normal.paragraph_format.line_spacing = 1.5
        normal.paragraph_format.space_after = Pt(4)
        for lvl, size in ((1, 15.0), (2, 12.5), (3, 11.0)):
            st = self.d.styles[f"Heading {lvl}"]
            style_font(st, HEI, size, bold=True)
            st.paragraph_format.space_before = Pt(14 if lvl == 1 else 10)
            st.paragraph_format.space_after = Pt(6)
            st.paragraph_format.line_spacing = 1.2

    def title(self, text: str) -> None:
        p = self.d.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_after = Pt(18)
        r = p.add_run(text)
        run_font(r, HEI)
        r.font.size = Pt(22)
        r.font.bold = True

    def h(self, text: str, level: int = 1) -> None:
        self.d.add_heading(text, level=level)

    def p(self, text: str, indent: bool = True) -> None:
        para = self.d.add_paragraph(text)
        if indent:
            para.paragraph_format.first_line_indent = Pt(21)

    def items(self, rows: list[str]) -> None:
        """一组短条目：行首写序号（1. 2. 3.），每组从 1 开始。"""
        for index, text in enumerate(rows, start=1):
            para = self.d.add_paragraph()
            para.paragraph_format.space_after = Pt(2)
            run_font(para.add_run(f"{index}. " + text), SONG)
        self.d.add_paragraph().paragraph_format.space_after = Pt(2)

    def img(self, name: str, caption: str, width_cm: float = 13.4) -> None:
        path = SHOTS / name
        self.pic += 1
        para = self.d.add_paragraph()
        para.alignment = WD_ALIGN_PARAGRAPH.CENTER
        para.paragraph_format.space_before = Pt(6)
        para.paragraph_format.space_after = Pt(2)
        para.paragraph_format.keep_with_next = True
        para.add_run().add_picture(str(path), width=Cm(width_cm))
        cap = self.d.add_paragraph()
        cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
        cap.paragraph_format.space_after = Pt(10)
        r = cap.add_run(f"图 {self.pic}  {caption}")
        run_font(r, SONG)
        r.font.size = Pt(9)


def build(doc: Doc) -> None:
    doc.title("《共生之缚》场景文档")

    doc.h("一、概况")
    doc.p("《共生之缚》是横版动作探索游戏，共六个场景：主菜单、序章、教学关、第一层、第二层、第三层。"
          "所有场景都由 GDScript 在运行时建出来，布局写在脚本里的一张数表上。")
    doc.items([
        "引擎与渲染：Godot 4.7.2，GL 兼容渲染器；视口 1280×720，canvas_items 拉伸。",
        "可视范围：高度 12 个角色身高，角色 28px，合计 336px；镜头缩放 2.143。",
        "角色碰撞盒：14×26px，脚底取碰撞盒下沿。",
        "场景宽度：教学关 7400，第一层 6160，第二层 5300，第三层 4300。",
        "地形做法：Polygon2D 多边形配 RectangleShape2D 碰撞，逐层代码生成。",
        "美术：主角 7 张分层 PNG；地形、道具、怪物全部代码建模。",
        "音效：127 个 wav，程序合成与真实录音混用。",
    ])

    doc.h("二、视觉基调")
    doc.p("六个场景共用一个冷色底子：背景压到 0.02 上下，石材 0.176 / 0.196 / 0.208，画面上只留边缘一线路亮。"
          "第一层偏青，第二层偏暖褐，第三层偏紫灰，走到哪一层一眼就能认出来。")
    doc.p("画面上的“亮”全部来自边缘线和小光点：")
    doc.items([
        "顶面亮边：沿整条地形轮廓画 2px 线，色 0.335；只画在能站人的水平顶面，侧面不留亮线。",
        "壁灯：暖黄光斑加灯架，只出现在墙面和柱头上。",
        "篝火与祭坛：火焰多边形逐帧抖动，再叠一层加色光斑。",
        "苔痕与孢子：低饱和绿点和小光点，交代潮湿与浮尘。",
        "血条告警：血量为 1 时全屏脉冲暗角，配一行“血量危险”。",
    ])

    doc.h("三、层级与画法")
    doc.p("场景从后往前分七层，每一层只放该放的东西：")
    doc.items([
        "z = -3：天空渐变、远景岩柱、雾、孢子。",
        "z = -2：背景板 Backdrop。",
        "z = -1：地面、平台、台阶、门框、道具底座。",
        "z = 0：玩家、敌人、掉落物。",
        "CanvasLayer 1：HUD，血条、目标文字、暂停菜单。",
        "CanvasLayer 20：开场黑幕，只留角色周围一圈可见。",
    ])
    doc.p("每块地面、平台、台阶的可见轮廓都是岩体形状：顶面两个点贴碰撞顶边，"
          "左右各鼓出 3~7px，底部挂 5~9px 碎岩，平台落在平地上时也读成一整块石头。")
    doc.p("石材纹理在世界坐标里统一铺：砌层 12px 一档，石块 20~58px 宽、7~15px 高、随机错位，"
          "竖缝每 120~260px 一溜，相邻两块地形的纹理是连续的。")

    doc.h("四、主菜单与序章")
    doc.img("01_menu.png", "主菜单：标题、开始与退出两个按钮，背景是同心环和两根拱柱的线稿")
    doc.p("主菜单上只有一个标题、两个按钮和底部两行操作提示，背景是同心环和拱柱的线稿。")
    doc.p("序章的画面全黑，只有角色周身一圈微光照出轮廓，影子用着色器逐像素画成烟；"
          "角色从高处坠下，镜头跟着下降，落地后黑幕慢慢散开，交到教学关。"
          "这一段只有着色器，没有背景板和物件，所以在文档里不放截图。")

    doc.h("五、教学关")
    doc.p("教学关是一条 7400px 长的横廊，八个环节按顺序排开，两环之间留足奔跑距离。"
          "地面顶边 y=659，从 0 铺到 5850；5850 到 6890 是悬崖，掉下去判死；"
          "右岸从 6890 接到 7400，祭坛和层门都摆在右岸。")
    doc.p("八个环节的站位（x 坐标 / 落脚面）：")
    doc.items([
        "移动：700 / 地面 659。平地，左侧是三层岩壁。",
        "跳跃：1300 / 跳台 571。长跳台 (1025,571,2695,90)。",
        "拾剑：2000 / 跳台 571。尸体与插在地上的铁剑。",
        "攻击：2700 / 跳台 571。稻草人甲。",
        "下劈：3160 / 跳台 571。下劈方台 (3300,440,200,131)，台前悬一根踏板。",
        "战斗：4100 / 坑底 659。这里生成一只史莱姆，玩家需要击杀它。",
        "拾取肢体：5580 / 地面 659。怪物尸体旁，篝火在 5700。",
        "献祭：6950 / 右岸 659。祭坛在层门左边，门在 7300。",
    ])
    doc.img("03_arena_spawn.png", "出生点：左侧三层岩壁，地表撒草簇与半埋碎石")
    doc.p("出生点左侧是一面三层岩壁，从 -420 一直延到贴着墙，内沿是锯齿断面，"
          "上面有五条裂缝、墙根苔和一盏极暗壁灯。地表全程撒着草簇和碎石，碎石露出不超过 5px，走过去不会绊脚。")
    doc.img("04_arena_ledge.png", "跳台：地面与平台同一套石材，顶边一条亮线勾出能站的位置")
    doc.img("05_arena_pogo.png", "下劈方台：方台立在跳台上，前方悬一根稻草人当踏板")
    doc.p("下劈方台高 131px，侧面打竖缝，顶面亮线只画在台顶；稻草人乙悬在方台前 54.6px，"
          "向下劈它，反弹正好落在台顶。")
    doc.img("06_arena_pit.png", "史莱姆坑：一只史莱姆从这里追上来，玩家需要击杀它")
    doc.p("这一段的坑底和两侧地面同高，地面是一条连续的整石，走过去不会有台阶或接缝。"
          "史莱姆顺着地面追人，玩家把它打死之后，掉落的肢体留在原地。")
    doc.img("07_arena_altar.png", "祭坛：落在右岸、层门左边，本体 44px 高，脚底贴地面 659")
    doc.img("08_arena_campfire.png", "篝火：火堆本体 y=637，石圈压在地面上，休一次回一颗心")
    doc.img("09_arena_chasm.png", "悬崖边：地面到 5850 为止，对岸靠四块悬空石台过去")
    doc.p("悬崖这一段没有地面，对岸靠四块石台当路；掉进中间山谷的玩家和怪物当场判死。"
          "过了悬崖先碰到祭坛，再往右 350px 是层门，献祭这一步在进门前必然经过。")

    doc.h("六、第一层 锈钟回廊")
    doc.img("12_floor1_hall.png", "钟厅：石柱、蜡台和地面的苔痕，吊钟在这一段的正中")
    doc.p("第一层宽 6160，钟厅地面顶边 y=760，跨度 1120~2760。吊钟在 x=2250，钟绳一直垂到地面，"
          "守钟人站在 1950，敲钟要先跟他说话；骨门在 2580，层门在 6000。"
          "地面是青灰色，砖缝和苔痕比教学关重。")

    doc.h("七、第二层 铸炉与圣坛")
    doc.img("13_floor2_forge.png", "铸炉厅：蒸汽机、工程师与宝箱，暖褐色调，壁面有竖缝与灯")
    doc.p("第二层宽 5300，平台从 (0,620) 一路降到 (3960,560)，形成一路向下的坡度。"
          "中央铸炉厅在 1080~1780，放蒸汽机与工程师；圣坛廊在 1880~2640，放祭司；封印门前厅在 3360~3860。"
          "两名 NPC 只能选一个，选完对面那条路封死。")

    doc.h("八、第三层 守门者之厅")
    doc.img("15_floor3_hall.png", "守门者之厅：石拱、火盆与插在地上的铁剑，紫灰色调")
    doc.p("第三层宽 4300。骑士像廊 1060~1620，断兵回廊 2200~2700，守门者之厅 2800~4200，"
          "两端是 -80 与 4200 的边界墙。厅里放石拱、火盆和一把半埋的铁剑，Boss 就在这一段。")

    doc.h("九、镜头与构图")
    doc.p("镜头是 Camera2D 跟人。水平方向按速度给 60px 前瞻，跑起来能提前看到落点；垂直方向落地时缓动回正，"
          "空中上下各留死区，上方 128px、下方 28px，普通跳跃不推镜头；水平差超过 480px（瞬移、复活）直接吸附。"
          "角色常驻屏幕中线下方 28px，六个场景都设了左右限幅，镜头不会推到场景外。")

    doc.h("十、氛围层")
    doc.p("每个场景都叠一层同样结构的氛围，参数按场景宽度铺：")
    doc.items([
        "雾：5 层椭圆，宽 560px，透明度 0.045~0.08，缓慢横移。",
        "孢子：50 颗，寿命 8s，向上飘。",
        "远景：两层岩柱剪影，越远越暗。",
        "暗角：血量为 1 触发，红色脉冲，配“血量危险”文字。",
    ])

    doc.h("十一、摆放与校准规则")
    doc.p("摆件和文字的位置都按下面几条算出来，改布局时不用逐个对坐标：")
    doc.items([
        "道具落地：量道具可见部分的最低点，向下打射线找脚下地面，整体平移对齐，误差 ≤1px。",
        "提示文字：文字中心定在这一环落脚面往上 3 个角色身高，即 84px。",
        "踏板：下劈用的稻草人乙悬在方台前 54.6px，向下劈它，反弹正好落到台顶。",
        "地形装饰：顶边与碰撞顶边误差 ≤1px，侧面鼓出 ≤10px。",
    ])

    doc.h("十二、回归测试")
    doc.p("场景相关的自动化测试和其余用例一起跑：scripts/test_all.ps1 依次执行数据管道、后端 pytest、"
          "每条 *_test.gd，全绿才算通过，目前共 72 条。其中直接盯着场景的有六条：")
    doc.items([
        "arena_layout_test：八环站位、层门位置、右岸宽度、镜头限幅。",
        "arena_terrain_layer_test：地形层级、方台侧面竖缝、装饰不越出碰撞盒。",
        "marker_clearance_test：八环提示离地高度、位置判定正反向。",
        "prop_grounding_test：五个道具贴地误差 ≤1px、踏板必须悬空。",
        "player_grounding_test：角色可见底边对齐脚底线，待机走路不被抬离地面。",
        "camera_spec_test：六个场景的镜头限幅与构图。",
    ])


def main() -> int:
    global OUT
    if len(sys.argv) > 1:
        # 允许指定输出路径：文档在 WPS/Word 里打开时原名会被锁住，先写到临时文件再替换
        OUT = Path(sys.argv[1]).resolve()
    doc = Doc()
    build(doc)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    doc.d.save(str(OUT))
    print(f"已生成 {OUT}（{OUT.stat().st_size / 1024:.0f} KB，{doc.pic} 张图）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
