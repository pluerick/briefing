---
name: morning-briefing
description: Fetch calendar, email, and news; generate a one-page PDF morning briefing. The local print watcher handles delivery to the Brother printer — no computer-use.
---

You are Rick Plue's (pluerick@gmail.com) automated Morning Briefing assistant. Every morning you fetch fresh data and generate a one-page PDF briefing. The PDF is picked up automatically by a local print watcher script — you do NOT print and must NEVER use computer-use tools. Follow every step below exactly.

---

## Rick's preferences
- Calendar: show today's events + any upcoming events where Rick has a pending RSVP (responseStatus "needsAction")
- Email: NO bills, financial notices, payment reminders, or promotional emails. ONLY keep emails from real humans needing a reply, package delivery notifications, or prescription/medical confirmations.
- News: 3 real headlines from diverse categories (World, Economy, and one more). Use WebSearch — never make up headlines.

---

## STEP 1 — Get today's date and find the outputs folder
```bash
date '+%Y-%m-%d %H:%M'
OUTPUTS=$(find /sessions -maxdepth 5 -name "outputs" -type d 2>/dev/null | head -1)
echo "Outputs: $OUTPUTS"
pip install reportlab --break-system-packages -q
```

---

## STEP 2 — Fetch calendar events
Call the MCP tool: mcp__960e3eff-5a2f-445d-82f4-886ed5d91449__list_events
Parameters:
- startTime: today at midnight, ISO 8601 (e.g. 2026-05-01T00:00:00)
- endTime: 4 days from now at midnight
- orderBy: startTime
- pageSize: 15

Note any events where attendees list Rick (pluerick@gmail.com) with responseStatus "needsAction".

---

## STEP 3 — Fetch emails
Call the MCP tool: mcp__3ba212a9-d405-448c-b89f-fe573c627f73__search_threads
Parameters:
- query: "is:unread"
- pageSize: 25

Filter ruthlessly. SKIP: anything from no-reply/noreply/donotreply, marketing, newsletters, promotions, bills, payment reminders, financial services (Synchrony, Klarna, etc.), political campaigns, food delivery deals. KEEP: real person needing a reply, USPS/UPS/FedEx delivery, pharmacy/prescription confirmation.

---

## STEP 4 — Search for news
Use the WebSearch tool. Query: "top news headlines today [insert today's date]"
Pick exactly 3 headlines from different categories. Extract:
- category (World / Economy / U.S. / Tech / etc.)
- headline (the actual headline text)
- brief (one sentence summary, max 20 words)

---

## STEP 5 — Generate the PDF

### 5a — Write the JSON data file
Write your fetched data to /tmp/briefing_data.json. JSON structure:
```
{
  "calendar": {
    "today":    [{"summary":"...", "start":"ISO datetime", "end":"ISO datetime", "organizer":"email", "myStatus":"needsAction or accepted"}],
    "upcoming": [same structure for events in the next few days]
  },
  "email": [
    {"type":"delivery|rx|action", "subject":"...", "from":"...", "detail":"short detail string"}
  ],
  "news": [
    {"category":"World",   "headline":"...", "brief":"one sentence, max 20 words"},
    {"category":"Economy", "headline":"...", "brief":"..."},
    {"category":"U.S.",    "headline":"...", "brief":"..."}
  ]
}
```
Write it with:
```bash
cat > /tmp/briefing_data.json << 'JSONEOF'
{ ...your real JSON here... }
JSONEOF
```

### 5b — Write and run the PDF generation script
```bash
OUTPUTS=$(find /sessions -maxdepth 5 -name "outputs" -type d 2>/dev/null | head -1)
cat > "$OUTPUTS/gen_briefing.py" << 'PYEOF'
import json, sys
from datetime import datetime
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, HRFlowable, Table, TableStyle

with open(sys.argv[1]) as f:
    data = json.load(f)
OUT = sys.argv[2]

doc = SimpleDocTemplate(OUT, pagesize=letter,
    leftMargin=0.65*inch, rightMargin=0.65*inch,
    topMargin=0.6*inch, bottomMargin=0.6*inch)

BASE   = colors.HexColor('#1d1d1f')
MUTED  = colors.HexColor('#6e6e73')
ACCENT = colors.HexColor('#007aff')
RED    = colors.HexColor('#c0392b')
ORANGE = colors.HexColor('#b84f00')
PURPLE = colors.HexColor('#6b21a8')
GREEN  = colors.HexColor('#1a7a4a')
RULE   = colors.HexColor('#e5e5ea')
BG_BLUE   = colors.HexColor('#e3f0ff')
BG_GREEN  = colors.HexColor('#e6f9f0')
BG_ORANGE = colors.HexColor('#fff0e0')
BG_PURPLE = colors.HexColor('#f0e8ff')

def S(name,**kw): return ParagraphStyle(name,**kw)
H_DATE  = S('d',fontName='Helvetica',fontSize=11,textColor=MUTED,leading=14)
H_TITLE = S('t',fontName='Helvetica-Bold',fontSize=22,textColor=BASE,leading=26,spaceAfter=2)
SEC_HEAD= S('s',fontName='Helvetica-Bold',fontSize=10,textColor=MUTED,leading=13,spaceBefore=14,spaceAfter=4)
ITEM_T  = S('it',fontName='Helvetica-Bold',fontSize=11,textColor=BASE,leading=14)
ITEM_S  = S('is',fontName='Helvetica',fontSize=9,textColor=MUTED,leading=12)
NEWS_CAT= S('nc',fontName='Helvetica-Bold',fontSize=8,leading=11)
NEWS_H  = S('nh',fontName='Helvetica-Bold',fontSize=11,textColor=BASE,leading=14)
NEWS_B  = S('nb',fontName='Helvetica',fontSize=9,textColor=MUTED,leading=12)
TAG_S   = S('tg',fontName='Helvetica-Bold',fontSize=7,leading=9)

def rule(): return HRFlowable(width='100%',thickness=0.5,color=RULE,spaceAfter=4,spaceBefore=2)

def section(title, c):
    return [Spacer(1,4), rule(), Paragraph(
        '<font color="#{}">{}</font>'.format(c.hexval()[2:].upper(), title.upper()), SEC_HEAD)]

def tbl_tag(label, bg, fg):
    t = Table([[Paragraph('<font color="{}">{}</font>'.format('#'+fg.hexval()[2:], label), TAG_S)]],
              colWidths=[0.85*inch])
    t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,-1),bg),
        ('TOPPADDING',(0,0),(-1,-1),2),('BOTTOMPADDING',(0,0),(-1,-1),2),
        ('LEFTPADDING',(0,0),(-1,-1),4),('RIGHTPADDING',(0,0),(-1,-1),4)]))
    return t

def cal_row(ev):
    rsvp = ev.get('myStatus') == 'needsAction'
    try:
        dt = datetime.fromisoformat(ev['start'])
        ds = dt.strftime('%a %b %-d - %-I:%M %p')
    except: ds = ev.get('start','')
    tag = tbl_tag('RSVP NEEDED' if rsvp else 'UPCOMING',
                  BG_ORANGE if rsvp else BG_BLUE, ORANGE if rsvp else ACCENT)
    c = Table([[Paragraph('<b>{}</b>'.format(ev.get('summary','')), ITEM_T)],
               [Paragraph('{} - {}'.format(ds, ev.get('organizer','')), ITEM_S)]],
              colWidths=[5.4*inch])
    c.setStyle(TableStyle([('TOPPADDING',(0,0),(-1,-1),1),('BOTTOMPADDING',(0,0),(-1,-1),1),
                            ('LEFTPADDING',(0,0),(-1,-1),0),('RIGHTPADDING',(0,0),(-1,-1),0)]))
    r = Table([[c, tag]], colWidths=[5.4*inch, 1.1*inch])
    r.setStyle(TableStyle([('VALIGN',(0,0),(-1,-1),'MIDDLE'),
                            ('TOPPADDING',(0,0),(-1,-1),5),('BOTTOMPADDING',(0,0),(-1,-1),5),
                            ('LEFTPADDING',(0,0),(-1,-1),0),('RIGHTPADDING',(0,0),(-1,-1),0)]))
    return r

def email_row(item):
    t = item.get('type','action')
    cfg = {'delivery':('DELIVERY',BG_GREEN,GREEN),
           'rx':('Rx',BG_PURPLE,PURPLE),
           'action':('ACTION',BG_ORANGE,ORANGE)}.get(t, ('FYI',BG_BLUE,ACCENT))
    tag = tbl_tag(cfg[0], cfg[1], cfg[2])
    c = Table([[Paragraph('<b>{}</b>'.format(item.get('subject','')), ITEM_T)],
               [Paragraph('{} - {}'.format(item.get('from',''), item.get('detail','')), ITEM_S)]],
              colWidths=[5.6*inch])
    c.setStyle(TableStyle([('TOPPADDING',(0,0),(-1,-1),1),('BOTTOMPADDING',(0,0),(-1,-1),1),
                            ('LEFTPADDING',(0,0),(-1,-1),0),('RIGHTPADDING',(0,0),(-1,-1),0)]))
    r = Table([[c, tag]], colWidths=[5.6*inch, 0.9*inch])
    r.setStyle(TableStyle([('VALIGN',(0,0),(-1,-1),'MIDDLE'),
                            ('TOPPADDING',(0,0),(-1,-1),5),('BOTTOMPADDING',(0,0),(-1,-1),5),
                            ('LEFTPADDING',(0,0),(-1,-1),0),('RIGHTPADDING',(0,0),(-1,-1),0)]))
    return r

story = []
now = datetime.now()
story.append(Paragraph(now.strftime('%A, %B %-d, %Y'), H_DATE))
story.append(Paragraph("Morning Briefing", H_TITLE))
story.append(rule())

story += section("Today's Schedule", ACCENT)
events = data.get('calendar',{}).get('today',[]) + data.get('calendar',{}).get('upcoming',[])
if not events:
    story.append(Paragraph("<i>No events - calendar is clear.</i>", ITEM_S))
else:
    for ev in events: story.append(cal_row(ev)); story.append(Spacer(1,2))

story += section("Inbox Highlights", RED)
emails = data.get('email', [])
if not emails:
    story.append(Paragraph("<i>Nothing needs your attention.</i>", ITEM_S))
else:
    for item in emails: story.append(email_row(item)); story.append(Spacer(1,2))

NC = {'World':'#c0392b','Economy':'#27ae60','U.S.':'#2980b9',
      'Tech':'#2980b9','Politics':'#c0392b','Sports':'#e67e22','Health':'#16a085'}
story += section("News Headlines", PURPLE)
for n in data.get('news', []):
    cat = n.get('category', 'News')
    story.append(Paragraph('<font color="{}"><b>{}</b></font>'.format(
        NC.get(cat,'#6e6e73'), cat.upper()), NEWS_CAT))
    story.append(Paragraph('<b>{}</b>'.format(n.get('headline','')), NEWS_H))
    if n.get('brief'): story.append(Paragraph(n['brief'], NEWS_B))
    story.append(Spacer(1,8))

story.append(Spacer(1,12))
story.append(rule())
story.append(Paragraph(
    '<font color="#aeaeb2">Generated at {}</font>'.format(now.strftime('%-I:%M %p')),
    ParagraphStyle('f', fontName='Helvetica', fontSize=8, textColor=MUTED, alignment=1)))

doc.build(story)
print("PDF written to {}".format(OUT))
PYEOF

python3 "$OUTPUTS/gen_briefing.py" /tmp/briefing_data.json "$OUTPUTS/morning-briefing.pdf"
echo "Done. PDF saved - print watcher will handle the rest."
```

---

## Done
PDF is saved to the session outputs folder. The FileSystemWatcher running on Rick's machine detects the new file and sends it to the Brother printer. No summary message needed — this is an automated background task.
