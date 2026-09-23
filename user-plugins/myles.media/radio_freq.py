# Shared broadcast dial frequency extraction for myles.media scripts.
# Keep in sync with MediaModel.extractRadioFrequency.
import re

_RE_DEC = re.compile(r"(\d{2,3})[.,](\d{1,2})\s*(FM|AM|MHz)?", re.I)
_RE_INT = re.compile(r"\b(\d{2,4})\s*(FM|AM)\b", re.I)


def extract_radio_frequency(text):
    s = str(text or "")
    if not s:
        return ""
    best = ""
    for m in _RE_DEC.finditer(s):
        try:
            whole = float(f"{m.group(1)}.{m.group(2)}")
        except Exception:
            continue
        band = (m.group(3) or "").upper().replace("MHZ", "FM")
        if not band:
            if 87 <= whole <= 108:
                band = "FM"
            elif 530 <= whole <= 1700:
                band = "AM"
            else:
                continue
        if band == "FM" and not (87 <= whole <= 108):
            continue
        if band == "AM" and not (530 <= whole <= 1700):
            continue
        decimals = 1 if len(m.group(2)) == 1 else min(2, len(m.group(2)))
        best = f"{whole:.{decimals}f} {band}"
        if band == "FM":
            return best
    for m in _RE_INT.finditer(s):
        try:
            n = int(m.group(1))
        except Exception:
            continue
        band = m.group(2).upper()
        if band == "FM" and not (87 <= n <= 108):
            continue
        if band == "AM" and not (530 <= n <= 1700):
            continue
        return f"{n} {band}"
    return best
