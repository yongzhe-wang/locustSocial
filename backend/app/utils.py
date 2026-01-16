import re

HTML_TAG_RE = re.compile(r"<[^>]+>")

def clean_text(s: str) -> str:
    if not s:
        return ""
    s = s.strip()
    s = HTML_TAG_RE.sub(" ", s)
    # s = re.sub(r"\s+", " ", s) # Don't collapse newlines
    return s[:4096]  # cap length
