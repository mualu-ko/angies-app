"""Merge the DDInter 2.0 export (ddinter_compact.txt) into the app's data.

ddinter_compact.txt was built from DDInter's 8 CSV files:
  NAMES section: every drug name in DDInter
  PAIRS section: cancerdrug|otherdrug|M (major) or m (moderate)

Run from the project folder:  python tools/apply_ddinter_compact.py
DDInter 2.0 is CC BY-NC-SA 4.0 (non-commercial use, with attribution).
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets", "data")
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "ddinter_compact.txt")

# DDInter uses US / INN names; patients in Kenya use these.
LOCAL_NAMES = {
    "acetaminophen": "paracetamol",
    "acetylsalicylic acid": "aspirin",
    "st. john's wort": "st john's wort",
    "glyburide": "glibenclamide",
    "salbutamol": "salbutamol",
}
ALIASES_FOR_STARTER = {
    "Paracetamol": ["Acetaminophen"],
    "Aspirin": ["Acetylsalicylic acid"],
    "St John's wort": ["St. John's Wort"],
    "Glibenclamide": ["Glyburide"],
}
ADVICE = {
    "major": "Major interaction: these can be dangerous together. Talk to your pharmacist or doctor before taking them.",
    "moderate": "Moderate interaction: your care team may need to adjust or monitor. Tell your pharmacist.",
}


def main():
    text = open(SRC, encoding="utf-8").read().splitlines()
    names, pairs, section = [], [], None
    for line in text:
        if line in ("NAMES", "PAIRS"):
            section = line
            continue
        if not line.strip():
            continue
        if section == "NAMES":
            names.append(line.strip())
        elif section == "PAIRS":
            drug, other, lvl = line.rsplit("|", 2)
            pairs.append((drug, other, "major" if lvl == "M" else "moderate"))

    # ---- medicines.json: starter list + all DDInter names
    med_path = os.path.join(ASSETS, "medicines.json")
    meds = json.load(open(med_path, encoding="utf-8"))
    by_lower = {m["name"].lower(): m for m in meds["medicines"]}
    for name, aliases in ALIASES_FOR_STARTER.items():
        m = by_lower.get(name.lower())
        if m:
            m["aliases"] = sorted(set(m.get("aliases", [])) | set(aliases))
    known = set(by_lower)
    for m in meds["medicines"]:
        known.update(a.lower() for a in m.get("aliases", []))
    added_names = 0
    for n in names:
        if n.lower() not in known and LOCAL_NAMES.get(n.lower(), "") not in known:
            meds["medicines"].append({"name": n, "category": "DDInter", "aliases": []})
            known.add(n.lower())
            added_names += 1
    meds["_note"] = ("Starter list (with Kenyan brands; entries with verify=true need checking) "
                     "plus DDInter 2.0 drug names (CC BY-NC-SA 4.0).")
    json.dump(meds, open(med_path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)

    # ---- interactions.json: keep hand-written entries, add DDInter pairs
    int_path = os.path.join(ASSETS, "interactions.json")
    inter = json.load(open(int_path, encoding="utf-8"))
    handwritten = [i for i in inter["interactions"] if i.get("source") != "ddinter"]
    have = {(i["drug"], i["with"]) for i in handwritten}
    out = list(handwritten)
    for drug, other, level in pairs:
        for w in {other, LOCAL_NAMES.get(other, other)}:
            if (drug, w) in have:
                continue
            have.add((drug, w))
            out.append({"drug": drug, "with": w, "type": "drug", "severity": level,
                        "advice": ADVICE[level], "source": "ddinter"})
    inter["interactions"] = out
    inter["source"] = "DDInter 2.0"
    inter["_note"] = ("Hand-written entries (clearer wording) plus DDInter 2.0 pairs for 24 oral cancer drugs. "
                      "CC BY-NC-SA 4.0. Pharmacy students should review the drugs featured in the demo.")
    json.dump(inter, open(int_path, "w", encoding="utf-8"), ensure_ascii=False)

    print(f"Drug names: {len(names)} in DDInter, {added_names} added; search list now {len(meds['medicines'])}")
    print(f"Interactions: {len(out)} total ({len(out) - len(handwritten)} from DDInter)")


if __name__ == "__main__":
    main()
