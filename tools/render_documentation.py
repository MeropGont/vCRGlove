"""Render the handbook from Marked tokens; run through build_documentation.mjs."""

import hashlib
import html
import json
import math
import re
import sys
import textwrap
from pathlib import Path, PurePosixPath

from pypdf import PdfReader
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, CondPageBreak, Frame, PageBreak, PageTemplate,
                               Paragraph, Preformatted, Spacer, Table, TableStyle)
from reportlab.platypus.tableofcontents import TableOfContents

if sys.argv[1] == '--check':
    subject = PdfReader(sys.argv[2]).metadata.subject
    if f'Source SHA256 {sys.argv[3]}' not in (subject or ''):
        raise SystemExit('Handbook is stale. Rebuild it after updating the source chapters.')
    print('Handbook matches all source chapters.')
    raise SystemExit(0)

manifest = json.loads(Path(sys.argv[1]).read_text())
output = Path(sys.argv[2])
font_dir = Path('/System/Library/Fonts/Supplemental')
if font_dir.exists():
    for name, file in [('Body', 'Arial.ttf'), ('BodyBold', 'Arial Bold.ttf'),
                       ('BodyItalic', 'Arial Italic.ttf'), ('BodyBoldItalic', 'Arial Bold Italic.ttf')]:
        pdfmetrics.registerFont(TTFont(name, str(font_dir / file)))
    pdfmetrics.registerFontFamily('Body', normal='Body', bold='BodyBold',
                                 italic='BodyItalic', boldItalic='BodyBoldItalic')
else:
    for name, base in [('Body', 'Helvetica'), ('BodyBold', 'Helvetica-Bold'),
                       ('BodyItalic', 'Helvetica-Oblique'), ('BodyBoldItalic', 'Helvetica-BoldOblique')]:
        pdfmetrics.registerFont(pdfmetrics.Font(name, base, 'WinAnsiEncoding'))
    pdfmetrics.registerFontFamily('Body', normal='Body', bold='BodyBold',
                                 italic='BodyItalic', boldItalic='BodyBoldItalic')

styles = getSampleStyleSheet()
styles.add(ParagraphStyle('Text', fontName='Body', fontSize=11, leading=15, spaceAfter=8))
styles.add(ParagraphStyle('SmallText', parent=styles['Text'], fontSize=9.5, leading=12.5))
styles.add(ParagraphStyle('Chapter', parent=styles['Text'], fontName='BodyBold', fontSize=22,
                         leading=27, spaceAfter=16, keepWithNext=True))
styles.add(ParagraphStyle('Section', parent=styles['Text'], fontName='BodyBold', fontSize=15,
                         leading=19, spaceBefore=14, spaceAfter=8, keepWithNext=True))
styles.add(ParagraphStyle('Subsection', parent=styles['Section'], fontSize=12, leading=16,
                         spaceBefore=10))
styles.add(ParagraphStyle('BulletText', parent=styles['Text'], leftIndent=14, firstLineIndent=-14))
styles.add(ParagraphStyle('CellText', parent=styles['Text'], fontSize=10, leading=13, spaceAfter=0))
styles.add(ParagraphStyle('CodeText', fontName='Courier', fontSize=8.4, leading=11,
                         spaceBefore=3, spaceAfter=10))
styles.add(ParagraphStyle('ContentsText', parent=styles['Text'], fontSize=12, leading=20))


def slug(text):
    return re.sub(r'\s+', '-', re.sub(r'[^\w\s-]', '', text.lower()))


def key(file, heading):
    return 'section-' + hashlib.sha256((file + '#' + slug(heading)).encode()).hexdigest()[:16]


targets = {}
for chapter in manifest['chapters']:
    for token in chapter['tokens']:
        if token['type'] == 'heading':
            targets[(chapter['file'], slug(token['text']))] = key(chapter['file'], token['text'])


def inline(tokens, file):
    result = []
    for token in tokens or []:
        kind = token['type']
        text = html.escape(token.get('text', ''))
        children = inline(token.get('tokens', []), file)
        if kind in ['text', 'escape']:
            result.append(children or text)
        elif kind == 'codespan':
            result.append(f'<font name="Courier" size="9">{text}</font>')
        elif kind == 'strong':
            result.append(f'<b>{children}</b>')
        elif kind == 'em':
            result.append(f'<i>{children}</i>')
        elif kind == 'br':
            result.append('<br/>')
        elif kind == 'link':
            href = token['href']
            if href.startswith(('https://', 'http://', 'mailto:')):
                result.append(f'<link href="{html.escape(href, quote=True)}" color="#225744">{children}</link>')
            else:
                location, _, anchor = href.partition('#')
                linked = str(PurePosixPath(file).parent / location) if location else file
                import posixpath
                linked = posixpath.normpath(linked)
                if not anchor and any(ch['file'] == linked for ch in manifest['chapters']):
                    first = next(t for t in next(ch for ch in manifest['chapters'] if ch['file'] == linked)['tokens'] if t['type'] == 'heading')
                    anchor = slug(first['text'])
                target = targets.get((linked, anchor))
                result.append(f'<link href="#{target}" color="#225744">{children}</link>' if target else children)
        elif kind == 'del':
            result.append(f'<strike>{children}</strike>')
        else:
            result.append(children or text)
    return ''.join(result)


def blocks(tokens, file):
    result = []
    for token in tokens:
        kind = token['type']
        if kind == 'heading':
            style = 'Chapter' if token['depth'] == 1 else 'Section' if token['depth'] == 2 else 'Subsection'
            paragraph = Paragraph(inline(token['tokens'], file), styles[style])
            paragraph.bookmark = key(file, token['text'])
            paragraph.outline_level = 0 if token['depth'] == 1 else 1
            paragraph.outline_title = token['text']
            result.append(paragraph)
        elif kind in ['paragraph', 'text']:
            result.append(Paragraph(inline(token.get('tokens'), file) or html.escape(token.get('text', '')), styles['Text']))
        elif kind == 'list':
            for index, item in enumerate(token['items']):
                prefix = str((token.get('start') or 1) + index) + '.' if token['ordered'] else '-'
                if item.get('task'):
                    prefix = '[x]' if item.get('checked') else '[ ]'
                children = blocks(item['tokens'], file)
                if children and isinstance(children[0], Paragraph):
                    first = children.pop(0)
                    result.append(Paragraph(f'{prefix} {first.text}', styles['BulletText']))
                result.extend(children)
        elif kind == 'blockquote':
            result.extend(blocks(token['tokens'], file))
        elif kind == 'code':
            lines = []
            for line in token['text'].splitlines():
                chunks = textwrap.wrap(line.expandtabs(4), width=94, replace_whitespace=False,
                                       drop_whitespace=False, break_long_words=True) or ['']
                if token.get('lang') in ['zsh', 'bash', 'sh']:
                    chunks = [chunk + ('\\' if index < len(chunks)-1 else '')
                              for index, chunk in enumerate(chunks)]
                lines.extend(chunks)
            result.append(Preformatted('\n'.join(lines), styles['CodeText']))
        elif kind == 'table':
            rows = [token['header']] + token['rows']
            cells = [[Paragraph(('<b>' if index == 0 else '') + inline(cell['tokens'], file)
                                + ('</b>' if index == 0 else ''), styles['CellText'])
                      for cell in row] for index, row in enumerate(rows)]
            weights = [math.sqrt(sum(len(row[col]['text']) for row in rows) / len(rows) + 15)
                       for col in range(len(rows[0]))]
            width = A4[0] - 92
            widths = [width * weight / sum(weights) for weight in weights]
            table = Table(cells, colWidths=widths, repeatRows=1, hAlign='LEFT')
            table.setStyle(TableStyle([
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#D9D9D9')),
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#E6EBE8')),
                ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                ('LEFTPADDING', (0, 0), (-1, -1), 7), ('RIGHTPADDING', (0, 0), (-1, -1), 7),
                ('TOPPADDING', (0, 0), (-1, -1), 7), ('BOTTOMPADDING', (0, 0), (-1, -1), 7),
            ]))
            if result and isinstance(result[-1], Paragraph) and getattr(result[-1], 'outline_level', None) == 1:
                caption = result.pop()
                caption.keepWithNext = False
                result.extend([CondPageBreak(150), caption])
            result.extend([table, Spacer(1, 11)])
        elif kind == 'hr':
            result.append(Spacer(1, 9))
        elif kind in ['space', 'checkbox']:
            continue
        else:
            raise ValueError(f'Unsupported Markdown block {kind}: {file}')
    return result


class Handbook(BaseDocTemplate):
    def afterFlowable(self, flowable):
        if hasattr(flowable, 'bookmark'):
            self.canv.bookmarkPage(flowable.bookmark)
            self.canv.addOutlineEntry(flowable.outline_title, flowable.bookmark,
                                      flowable.outline_level, closed=False)
            if flowable.outline_level == 0:
                self.notify('TOCEntry', (0, flowable.outline_title, self.page, flowable.bookmark))


def page_frame(canvas, doc):
    canvas.saveState()
    canvas.setFont('Body', 8)
    canvas.drawString(46, A4[1] - 28, 'vCRGlove Project Handbook')
    canvas.drawRightString(A4[0] - 46, A4[1] - 28, manifest['date'])
    canvas.drawString(46, 25, 'Implementation reference. Study approval and physical validation are separate.')
    canvas.drawRightString(A4[0] - 46, 25, str(doc.page))
    canvas.restoreState()


document = Handbook(str(output), pagesize=A4, leftMargin=46, rightMargin=46,
                    topMargin=49, bottomMargin=44, title='vCRGlove Project Handbook',
                    author='ICNS', subject=f'Source SHA256 {manifest["sourceHash"]}')
document.addPageTemplates(PageTemplate(id='body', frames=[Frame(46, 44, A4[0] - 92, A4[1] - 93,
                                                              leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)],
                                      onPage=page_frame))
story = [Paragraph('vCRGlove Project Handbook', styles['Chapter']),
         Paragraph('A readable companion to the project documentation', styles['Section']),
         Paragraph('Setup, data formats, release steps and physical testing. This PDF is generated from the Markdown sources so the two formats can stay consistent.', styles['Text']),
         Paragraph(f'Review date {manifest["date"]}. This is an implementation reference, not patient information or a clinical protocol.', styles['Text']),
         Paragraph('Contents', styles['Section'])]
toc = TableOfContents()
toc.levelStyles = [styles['ContentsText']]
story.append(toc)
for chapter in manifest['chapters']:
    story.append(PageBreak())
    story.extend(blocks(chapter['tokens'], chapter['file']))
document.multiBuild(story)
reader = PdfReader(str(output))
assert len(reader.pages) > 1 and manifest['sourceHash'] in reader.metadata.subject
print(f'Handbook written: {len(reader.pages)} pages; source hash {manifest["sourceHash"][:12]}.')
