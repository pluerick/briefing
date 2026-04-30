# Generate a Morning Briefing PDF locally

## 1) Install dependency
```bash
python3 -m pip install reportlab
```

## 2) Create your data JSON
Start from the included sample:
```bash
cp briefing_data.sample.json briefing_data.json
```
Edit `briefing_data.json` with your real calendar/email/news data.

## 3) Generate the PDF
```bash
python3 gen_briefing.py briefing_data.json morning-briefing.pdf
```

## 4) Print or watch
If you're using the PowerShell watcher in this repo, place or copy the generated PDF where that watcher monitors for print jobs.
