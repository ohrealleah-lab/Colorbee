#!/usr/bin/env python3
"""Writes build/Known Good Review/index.html: each Adjust Photo known-good picture beside the photo it started from,
for looking them over by eye after `make known-good`."""
import html
import os

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
references = os.path.join(root, "TestImages", "Known Good")
review = os.path.join(root, "build", "Known Good Review")

rows = []
for name in sorted(os.listdir(references)):
    if not name.endswith(".png"):
        continue
    case = name[:-4]
    with open(os.path.join(review, case + ".photo"), encoding="utf-8") as file:
        photo = file.read()
    before = photo + ".png"
    after = os.path.relpath(os.path.join(references, name), review)
    rows.append(f'<figure><figcaption>{html.escape(case)} <span>on {html.escape(photo)}</span></figcaption>'
                f'<img src="{html.escape(before)}" alt="Before"><img src="{html.escape(after)}" alt="After"></figure>\n')

page = f"""<!doctype html>
<meta charset="utf-8">
<title>Known-good Adjust Photo pictures</title>
<style>
  body {{ font: 14px -apple-system, sans-serif; margin: 24px; background: #fff; color: #222; }}
  @media (prefers-color-scheme: dark) {{ body {{ background: #1e1e1e; color: #ddd; }} }}
  figure {{ margin: 0 0 20px; }}
  figcaption {{ font-weight: 600; margin-bottom: 6px; }}
  figcaption span {{ font-weight: 400; opacity: 0.6; }}
  img {{ width: 320px; height: auto; margin-right: 8px; }}
</style>
<h1>Known-good Adjust Photo pictures</h1>
<p>Before on the left, after on the right. Each should look like what its control is meant to do.</p>
{''.join(rows)}"""
with open(os.path.join(review, "index.html"), "w", encoding="utf-8") as out:
    out.write(page)
print('Look them over: open "build/Known Good Review/index.html"')
