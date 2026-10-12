"""Replace clipped preview pictures with complete phone screenshots."""

from pathlib import Path
import os

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Inches
from PIL import Image


ROOT = Path(__file__).parent
SCREENS = ROOT / "screens"
COMPLETE = SCREENS / "complete"
COMPLETE.mkdir(exist_ok=True)
DOCX = ROOT / "Crest-经营分析手机端UI规划.docx"

modules = (
    "dashboard",
    "orders",
    "order-detail-chart",
    "order-detail-table",
    "products",
    "labor",
    "alerts",
)


def complete_phone(module: str, theme: str) -> Path:
    source = SCREENS / f"{module}-{theme}-current-full.jpg"
    target = COMPLETE / f"{module}-{theme}.png"
    with Image.open(source) as screenshot:
        width, height = screenshot.size
        phone_width = 390
        left = (width - phone_width) // 2
        # The preview renders a centered 390-pixel phone with 28-pixel outer margins.
        phone = screenshot.crop((left, 27, left + phone_width, height - 27))
        phone.save(target, "PNG")
    return target


document = Document(DOCX)
assert len(document.tables) == len(modules), "Screenshot table structure changed"
assert len(document.inline_shapes) == len(modules) * 2, "Unexpected picture count"
widths = [shape.width for shape in document.inline_shapes]

# A digital-first, taller page fits each complete phone at the original readable width.
for section in document.sections:
    section.page_height = Inches(18.5)

for table_index, module in enumerate(modules):
    table = document.tables[table_index]
    for theme_index, theme in enumerate(("dark", "light")):
        cell = table.cell(1, theme_index)
        cell.text = ""
        paragraph = cell.paragraphs[0]
        paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
        paragraph.add_run().add_picture(
            str(complete_phone(module, theme)),
            width=widths[table_index * 2 + theme_index],
        )

temporary = DOCX.with_suffix(".full-screenshots.docx")
document.save(temporary)
os.replace(temporary, DOCX)
print(f"Replaced {len(modules) * 2} screenshots in {DOCX}")
