#!/usr/bin/env python3
"""mail-janitor — scheduled, age-aware anti-buildup sweep for the Gmail accounts.

Three tiers (same model as the interactive cleanup):
  PRESERVE  — people, history, finance, anything personal  -> never touched
  TXN       — receipts/orders/bookings                     -> trashed when older than MJ_TXN_MAX_AGE_DAYS
  NOISE     — promo/streaming/social/newsletters/bot-noise  -> trashed at any age

ALWAYS excludes the Family-Friends label and Sent. Trash is recoverable (30 days);
nothing is hard-deleted. DRY-RUN (default) only reports; set MJ_DRY_RUN=0 to act.
Posts a summary to hwc-notify. Stdlib only.

Env (set by the NixOS unit):
  MJ_ACCOUNTS         JSON: [{"name":"personal","email":"..","secret":"/run/agenix/.."}, ...]
  MJ_DRY_RUN          "1" (default) | "0"
  MJ_TXN_MAX_AGE_DAYS receipts older than this are trashed (default 365)
  MJ_NOTIFY_URL       hwc-notify endpoint (optional)
  MJ_NOW_TS           unix seconds "now" (the unit injects it; avoids wall-clock in logic)
"""
import imaplib, os, sys, json, re, email.utils, urllib.request
from datetime import datetime, timezone
from collections import Counter

DRY      = os.environ.get("MJ_DRY_RUN", "1") != "0"
MAXAGE   = int(os.environ.get("MJ_TXN_MAX_AGE_DAYS", "365"))
NOTIFY   = os.environ.get("MJ_NOTIFY_URL", "")
NOW      = float(os.environ.get("MJ_NOW_TS", "0")) or None
ACCOUNTS = json.loads(os.environ.get("MJ_ACCOUNTS", "[]"))

FREE={"gmail.com","yahoo.com","aol.com","icloud.com","me.com","mac.com","hotmail.com","outlook.com","comcast.net","msn.com","live.com","mcn.net","proton.me","ymail.com","yahoo.co.uk"}
ESP=("mailchimpapp","mc-ws.com","ccsend","sendgrid","rsgsv","mcsv","sparkpost","mailgun","hubspot","sendinblue","klaviyo","cmail","list-manage","mailerlite","constantcontact","bnc3","sendi","mktomail","exct.net","icpbounce")
NOISE_LOCAL=("no-reply","noreply","donotreply","do-not-reply","notification","notify","newsletter","mailer","marketing@","promo","deals","offers@","email@")
RETAIL=("amazon.","ebay.","rei.com","bestbuy","homedepot","lowes","walmart","target.com","etsy","wayfair","jossandmain","cvs.com","walgreens","dell.com","newegg","soundcore","all-clad","groupon","yardhouse","craigslist","ticketmaster","stubhub","uber.com","lyft.com","doordash","grubhub","instacart")
TXN_LOCAL=("order","receipt","shipment","shipping","tracking","invoice","billing","payment","confirm","auto-confirm","store-news","purchase")
STREAM=("hbomax","primevideo","netflix","spotify","hulu","discoveryplus","youtube.com","disneyplus","amazonmusic","cduniverse","paramount","peacock","audible")
SOCIAL=("facebookmail","nextdoor","linkedin","twitter","instagram","pinterest","locals.com","meetup","reddit")

def classify(a, subj):
    a=a.lower(); dom=a.split("@",1)[1] if "@" in a else ""; local=a.split("@",1)[0] if "@" in a else a
    if any(s in a for s in STREAM) or any(s in a for s in SOCIAL): return "NOISE"
    if any(e in dom for e in ESP): return "NOISE"
    if any(n in local for n in NOISE_LOCAL) and dom not in FREE:
        if any(tk in (a+" "+subj.lower()) for tk in TXN_LOCAL) or any(r in a for r in RETAIL): return "TXN"
        return "NOISE"
    if any(r in a for r in RETAIL): return "TXN"
    if any(tk in subj.lower() for tk in TXN_LOCAL) and dom not in FREE and ".edu" not in dom and ".gov" not in dom: return "TXN"
    return "PRESERVE"

def age_days(dstr):
    try:
        dt=email.utils.parsedate_to_datetime(dstr)
        if dt.tzinfo is None: dt=dt.replace(tzinfo=timezone.utc)
    except Exception:
        return None
    now=datetime.fromtimestamp(NOW, timezone.utc) if NOW else datetime.now(timezone.utc)
    return (now - dt).days

def sweep(acct):
    with open(acct["secret"]) as f: pw=f.read().strip()
    M=imaplib.IMAP4_SSL("imap.gmail.com",993); M.login(acct["email"],pw)
    M.select('"[Gmail]/All Mail"', readonly=DRY)
    t,d=M.uid("SEARCH","X-GM-RAW",'"-label:Family-Friends -in:sent -in:trash"')
    uids=d[0].split() if d and d[0] else []
    kill=[]; sen=Counter(); scanned=len(uids)
    for i in range(0,len(uids),200):
        t,fd=M.uid("FETCH",b",".join(uids[i:i+200]),"(UID BODY.PEEK[HEADER.FIELDS (DATE FROM SUBJECT)])")
        for it in fd:
            if not (isinstance(it,tuple) and it[1]): continue
            um=re.search(rb"UID (\d+)",it[0])
            if not um: continue
            h={}
            for line in it[1].decode("utf-8","replace").splitlines():
                if ":" in line: k,v=line.split(":",1); h[k.strip().lower()]=v.strip()
            a=email.utils.parseaddr(h.get("from",""))[1].lower()
            if not a or a==acct["email"]: continue
            b=classify(a,h.get("subject",""))
            if b=="NOISE":
                kill.append(um.group(1)); sen[a]+=1
            elif b=="TXN":
                ad=age_days(h.get("date",""))
                if ad is None or ad>MAXAGE: kill.append(um.group(1)); sen[a]+=1
    trashed=0
    if not DRY and kill:
        for i in range(0,len(kill),300):
            if M.uid("MOVE",b",".join(kill[i:i+300]),'"[Gmail]/Trash"')[0]=="OK": trashed+=len(kill[i:i+300])
    M.logout()
    return {"account":acct["name"],"scanned":scanned,"target":len(kill),"trashed":trashed,"top":sen.most_common(6)}

def notify(results):
    if not NOTIFY: return
    mode="DRY-RUN (nothing trashed)" if DRY else "ACTIVE"
    lines=[f"mail-janitor {mode} — receipts kept < {MAXAGE}d"]
    for r in results:
        verb="would trash" if DRY else "trashed"
        lines.append(f"• {r['account']}: {verb} {r['target']} of {r['scanned']} (noise + old receipts)")
    body="\n".join(lines)
    payload={"title":f"mail-janitor {mode}","topic":"nightly-builds","source":"mail-janitor","priority":4,"body":body}
    try:
        req=urllib.request.Request(NOTIFY,data=json.dumps(payload).encode(),
                                   headers={"Content-Type":"application/json"})
        urllib.request.urlopen(req,timeout=15).read()
    except Exception as e:
        print(f"notify failed: {e}", file=sys.stderr)

def main():
    if not ACCOUNTS:
        print("no MJ_ACCOUNTS configured", file=sys.stderr); sys.exit(1)
    results=[sweep(a) for a in ACCOUNTS]
    for r in results:
        print(f"{r['account']}: scanned={r['scanned']} target={r['target']} trashed={r['trashed']}")
        for a,n in r["top"]: print(f"    {n:>4}  {a}")
    notify(results)

if __name__=="__main__":
    main()
