"""Turn docs/GUIDE.md and CHANGELOG.md into pages (docs/GUIDE.html, docs/CHANGELOG.html) MALLET's Help menu opens.

Handles what the guide uses: headings, paragraphs, bullet and numbered lists (with wrapped lines), tables, **bold**,
*italic*, `code`, [links](#anchors) and --- rules. Run: python tools/guide_html.py
"""
import html
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def anchor(title):
    a = re.sub(r'[^a-z0-9 -]', '', title.lower()).strip().replace(' ', '-')
    return a


def inline(t):
    t = html.escape(t, quote=False)
    t = re.sub(r'`([^`]+)`', r'<code>\1</code>', t)
    t = re.sub(r'\*\*([^*]+)\*\*', r'<b>\1</b>', t)
    t = re.sub(r'(?<![*\w])\*([^*]+)\*(?!\w)', r'<i>\1</i>', t)
    t = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', t)
    return t


def convert(md):
    out = []
    lines = md.split('\n')
    i = 0
    para = []

    def flush():
        if para:
            out.append('<p>%s</p>' % inline(' '.join(para)))
            para.clear()

    while i < len(lines):
        ln = lines[i]
        s = ln.strip()
        if not s:
            flush()
            i += 1
            continue
        m = re.match(r'^(#{1,3}) (.*)$', ln)
        if m:
            flush()
            n = len(m.group(1))
            out.append('<h%d id="%s">%s</h%d>' % (n, anchor(m.group(2)), inline(m.group(2)), n))
            i += 1
            continue
        if s == '---':
            flush()
            out.append('<hr>')
            i += 1
            continue
        if s.startswith('|'):
            flush()
            rows = []
            while i < len(lines) and lines[i].strip().startswith('|'):
                rows.append([c.strip() for c in lines[i].strip().strip('|').split('|')])
                i += 1
            out.append('<table>')
            out.append('<tr>%s</tr>' % ''.join('<th>%s</th>' % inline(c) for c in rows[0]))
            for r in rows[2:]:
                out.append('<tr>%s</tr>' % ''.join('<td>%s</td>' % inline(c) for c in r))
            out.append('</table>')
            continue
        m = re.match(r'^(\s*)(-|\d+\.) (.*)$', ln)
        if m:
            flush()
            tag = 'ol' if m.group(2)[0].isdigit() else 'ul'
            items = []
            while i < len(lines):
                m2 = re.match(r'^(\s*)(-|\d+\.) (.*)$', lines[i])
                if m2 and not m2.group(1):
                    items.append(m2.group(3))
                elif lines[i].startswith('  ') and lines[i].strip() and items:
                    items[-1] += ' ' + lines[i].strip()
                else:
                    break
                i += 1
            out.append('<%s>%s</%s>' % (tag, ''.join('<li>%s</li>' % inline(t) for t in items), tag))
            continue
        para.append(s)
        i += 1
    flush()
    return '\n'.join(out)


CSS = """
:root { color-scheme: dark; --bg: #1c1f26; --panel: #252a33; --text: #dde2ea; --dim: #9aa3b2; --accent: #6cb6ff; --line: #3a404c; }
body { background: var(--bg); color: var(--text); font: 16px/1.55 "Segoe UI", system-ui, sans-serif; margin: 0; }
main { max-width: 900px; margin: 0 auto; padding: 32px 20px 80px; }
h1 { font-size: 34px; margin: 0 0 12px; }
h2 { font-size: 24px; margin: 40px 0 10px; padding-top: 12px; border-top: 1px solid var(--line); }
h3 { font-size: 19px; margin: 24px 0 8px; }
a { color: var(--accent); }
code { background: var(--panel); padding: 1px 5px; border-radius: 4px; font-size: 14px; }
table { border-collapse: collapse; margin: 12px 0; width: 100%; }
th, td { border: 1px solid var(--line); padding: 6px 10px; text-align: left; vertical-align: top; }
th { background: var(--panel); }
hr { border: 0; border-top: 1px solid var(--line); margin: 24px 0; }
li { margin: 4px 0; }
"""


PAGES = [('docs/GUIDE.md', 'docs/GUIDE.html', 'The MALLET guide'),
         ('CHANGELOG.md', 'docs/CHANGELOG.html', "What's new in MALLET")]


def main():
    for src, dst, title in PAGES:
        body = convert(io.open(os.path.join(ROOT, src), encoding='utf-8').read())
        page = ('<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
                '<meta name="viewport" content="width=device-width, initial-scale=1">'
                '<title>%s</title><style>%s</style></head><body><main>\n%s\n</main></body></html>\n') % (title, CSS, body)
        io.open(os.path.join(ROOT, dst), 'w', encoding='utf-8', newline='\n').write(page)
        print('wrote', dst, len(page), 'bytes')


if __name__ == '__main__':
    sys.exit(main())
