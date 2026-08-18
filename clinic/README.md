# vCRGlove — Clinical Data Handoff

## Folder contents

| File | Description |
|---|---|
| `vCRGlove_Clinical_Dashboard.ipynb` | Jupyter Notebook — load CSV exports, generate trend plots, pre/post comparison, Excel export |
| `README.md` | This file |

Place exported CSV files (`metrics-*.csv`, `samples-*.csv`) **in this folder** before running the notebook.

---

## Quick start

```bash
pip install pandas matplotlib seaborn scipy openpyxl notebook
jupyter notebook vCRGlove_Clinical_Dashboard.ipynb
```

---

## Data flow

```
iPhone (vCRGlove app)
   └─ Movement Test → Export → "CSV — metrics per trial"
         ↓  AirDrop / Mail
clinic/
   metrics-YYYYMMDD-HHmmss.csv   ← one row per trial
   samples-YYYYMMDD-HHmmss.csv   ← raw signal (optional, for signal plots)
         ↓  Jupyter Notebook
   vCRGlove_export.xlsx           ← Sheets: Trials / Session averages / Pre-Post Delta
   trend_<patient>_<side>.pdf     ← longitudinal trend plot per patient
   pre_post_comparison.pdf        ← boxplots + Wilcoxon p-values
```

---

## Privacy

- The app records only a **pseudonymized `patient_id`** (set in Settings).  
- No real names, DOB, or health identifiers are stored in the export files.  
- The mapping table (pseudonym → patient) must be stored separately and securely by the clinic.
