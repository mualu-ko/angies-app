"""Build the app's medicine list and interaction data from DDInter 2.0.

1. Download the DDInter CSV files (ddinter_downloads_code_*.csv) from
   https://ddinter2.scbdd.com/download/ into tools/ddinter/
2. Run:  python tools/ddinter_import.py
3. Rebuild the app.

DDInter data is CC BY-NC-SA 4.0: free for this non-commercial project,
with attribution. A commercial release needs a licensed database.

The CSVs give drug pairs and a level (Major / Moderate / Minor / Unknown)
but no patient wording, so the advice text below is generic. The pharmacy
students should review the interactions for the cancer drugs we feature.
"""
import csv
import glob
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ASSETS = os.path.join(ROOT, "assets", "data")

# Cancer drugs the app has full information for (ids in drugs.json).
CANCER_DRUGS = {"capecitabine", "imatinib", "tamoxifen"}

ADVICE = {
    "major": "Major interaction: these can be dangerous together. Talk to your pharmacist or doctor before taking them.",
    "moderate": "Moderate interaction: your care team may need to adjust or monitor. Tell your pharmacist.",
}


def main():
    files = glob.glob(os.path.join(HERE, "ddinter", "ddinter_downloads_code_*.csv"))
    if not files:
        raise SystemExit("No DDInter CSV files found in tools/ddinter/")

    names = set()
    pairs = {}
    for f in files:
        with open(f, newline="", encoding="utf-8") as fh:
            for row in csv.DictReader(fh):
                a, b = row["Drug_A"].strip(), row["Drug_B"].strip()
                level = row.get("Level", "").strip().lower()
                names.update([a, b])
                for x, y in ((a, b), (b, a)):
                    if x.lower() in CANCER_DRUGS and level in ADVICE:
                        key = (x.lower(), y.lower())
                        # keep the most severe level seen
                        if key not in pairs or (level == "major" and pairs[key] != "major"):
                            pairs[key] = level

    # Merge with the starter list so categories, brand names and herbal items stay.
    med_path = os.path.join(ASSETS, "medicines.json")
    meds = json.load(open(med_path, encoding="utf-8"))
    known = {m["name"].lower() for m in meds["medicines"]}
    for n in sorted(names):
        if n.lower() not in known:
            meds["medicines"].append({"name": n, "category": "DDInter", "aliases": []})
    meds["_note"] = "Starter list plus DDInter 2.0 drug names (CC BY-NC-SA 4.0)."
    json.dump(meds, open(med_path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)

    # Keep the hand-written entries (better wording); add DDInter pairs not already there.
    int_path = os.path.join(ASSETS, "interactions.json")
    inter = json.load(open(int_path, encoding="utf-8"))
    have = {(i["drug"], i["with"]) for i in inter["interactions"]}
    added = 0
    for (drug, other), level in sorted(pairs.items()):
        if (drug, other) in have:
            continue
        inter["interactions"].append(
            {"drug": drug, "with": other, "type": "drug", "severity": level, "advice": ADVICE[level]}
        )
        added += 1
    inter["source"] = "DDInter 2.0"
    json.dump(inter, open(int_path, "w", encoding="utf-8"), indent=2, ensure_ascii=False)

    print(f"Medicines in search list: {len(meds['medicines'])}")
    print(f"Interactions added for {', '.join(sorted(CANCER_DRUGS))}: {added}")


if __name__ == "__main__":
    main()
