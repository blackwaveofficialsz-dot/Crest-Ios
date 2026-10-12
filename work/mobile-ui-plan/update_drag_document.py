"""Add the agreed chart-drag behavior to the existing mobile UI plan."""

from pathlib import Path
import os

from docx import Document


DOCX = Path(__file__).with_name("Crest-经营分析手机端UI规划.docx")

REPLACEMENTS = {
    "当前交互  柱图左右滑动并点选查看门店明细；趋势门店可单选、多选、全选；支持 7/30 日切换和沿线查看单日数据。":
        "柱图左右滑动并点选查看门店明细；趋势门店可单选、多选、全选。折线图默认展示最近 30 日，向右拖动回看更早日期、向左拖动返回；点击折线查看单日数据，也可切换 7 日。",
    "当前交互  点击排名行直接打开该店详情，不在列表原地展开；详情支持折线图/数据表切换与 7/30 日周期。":
        "点击排名行直接打开该店详情，不在列表原地展开；详情默认展示最近 30 日，可在折线图和数据表之间切换，也可切换 7 日。",
    "趋势交互  折线图与数据表切换；支持 7/30 日，并可沿线查看单日订单数及同期变化。":
        "折线图默认展示最近 30 日；向右拖动回看更早日期、向左拖动返回，点击折线查看单日订单数及同期变化；也可切换 7 日。",
    "状态保持  切换折线图/数据表时，保留已选门店与 7/30 日周期。":
        "切换折线图/数据表时，保留已选门店、7/30 日周期和当前可见日期范围；数据表同步展示该范围内的逐日数据。",
}


document = Document(DOCX)
found = set()
for paragraph in document.paragraphs:
    old = paragraph.text
    if old not in REPLACEMENTS:
        continue
    assert len(paragraph.runs) == 2, f"Unexpected runs: {old}"
    assert paragraph.runs[0].bold, f"Missing label: {old}"
    paragraph.runs[1].text = REPLACEMENTS[old]
    found.add(old)

assert found == set(REPLACEMENTS), f"Missing paragraphs: {set(REPLACEMENTS) - found}"
temporary = DOCX.with_suffix(".drag-update.docx")
document.save(temporary)
os.replace(temporary, DOCX)
print(f"Updated {len(found)} existing paragraphs in {DOCX}")
