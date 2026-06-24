#!/usr/bin/env python3
"""mail-janitor — scheduled, age-aware anti-buildup sweep for the Gmail accounts.

Tiers (see classify):
  PRESERVE  — people, history, finance, .gov filings, calendar invites,
              security/account alerts  -> never touched
  TXN       — receipts/orders          -> trashed when older than MJ_TXN_MAX_AGE_DAYS
  TRIAGE    — newsletters              -> moved to the "Newsletters-Triage" label
              (out of the way for review), then trashed once they've sat in triage
              longer than MJ_TRIAGE_MAX_AGE_DAYS — UNLESS you star them or apply a
              keep/Family-Friends label. The 30-day clock starts when the message
              ENTERS triage (tracked in a state file), not its send date, so the
              existing backlog gets a full review window.
  NOISE     — promo/streaming/social/ESP/bot-noise -> trashed at any age

ALWAYS excludes the Family-Friends label and Sent. Trash is 30-day recoverable.
DRY-RUN (default) only reports. Stdlib only.

Env (set by the NixOS unit):
  MJ_ACCOUNTS            JSON: [{"name","email","secret"}, ...]
  MJ_DRY_RUN            "1" (default) | "0"
  MJ_TXN_MAX_AGE_DAYS   default 365
  MJ_TRIAGE_MAX_AGE_DAYS default 30
  MJ_STATE_DIR          triage-clock state dir (default ~/.local/state/mail-janitor)
  MJ_NOTIFY_URL         hwc-notify endpoint (optional)
"""
import imaplib, os, sys, json, re, email.utils, urllib.request
from datetime import datetime, timezone
from collections import Counter

DRY        = os.environ.get("MJ_DRY_RUN", "1") != "0"
TXN_MAX    = int(os.environ.get("MJ_TXN_MAX_AGE_DAYS", "365"))
TRIAGE_MAX = int(os.environ.get("MJ_TRIAGE_MAX_AGE_DAYS", "30"))
STATE_DIR  = os.environ.get("MJ_STATE_DIR", os.path.expanduser("~/.local/state/mail-janitor"))
NOTIFY     = os.environ.get("MJ_NOTIFY_URL", "")
ACCOUNTS   = json.loads(os.environ.get("MJ_ACCOUNTS", "[]"))
TRIAGE_LABEL = "Newsletters-Triage"

FREE={"gmail.com","yahoo.com","aol.com","icloud.com","me.com","mac.com","hotmail.com","outlook.com","comcast.net","msn.com","live.com","mcn.net","proton.me","ymail.com","yahoo.co.uk"}
ESP=("mailchimpapp","mc-ws.com","ccsend","sendgrid","rsgsv","mcsv","sparkpost","mailgun","hubspot","sendinblue","klaviyo","cmail","list-manage","mailerlite","constantcontact","bnc3","sendi","mktomail","exct.net","icpbounce")
NOISE_LOCAL=("no-reply","noreply","donotreply","do-not-reply","notification","notify","mailer","marketing@","promo","deals","offers@","email@")
NEWS_LOCAL=("newsletter","news@","digest","bulletin","weekly@","weekly-")
RETAIL=("amazon.","ebay.","rei.com","bestbuy","homedepot","lowes","walmart","target.com","etsy","wayfair","jossandmain","cvs.com","walgreens","dell.com","newegg","soundcore","all-clad","groupon","yardhouse","craigslist","ticketmaster","stubhub","uber.com","lyft.com","doordash","grubhub","instacart")
TXN_LOCAL=("order","receipt","shipment","shipping","tracking","invoice","billing","payment","confirm","auto-confirm","store-news","purchase")
STREAM=("hbomax","primevideo","netflix","spotify","hulu","discoveryplus","youtube.com","disneyplus","amazonmusic","cduniverse","paramount","peacock","audible")
SOCIAL=("facebookmail","nextdoor","linkedin","twitter","instagram","pinterest","locals.com","meetup","reddit")
SEC=("security","verif","2fa","login","password")

def classify(a, subj):
    a=a.lower(); dom=a.split("@",1)[1] if "@" in a else ""; local=a.split("@",1)[0] if "@" in a else a
    # --- PRESERVE allowlist (override) — these were false-positives in NOISE ---
    if ".gov" in dom: return "PRESERVE"                                   # govt filings
    if "calendar." in dom: return "PRESERVE"                             # meeting invites
    if ("ads" not in a) and ("accounts.google.com" in dom or any(k in local for k in SEC)):
        return "PRESERVE"                                               # security/account alerts
    # --- newsletters -> TRIAGE (collect for review, don't trash outright) ---
    if any(n in local for n in NEWS_LOCAL): return "TRIAGE"
    # --- clear junk ---
    if any(s in a for s in STREAM) or any(s in a for s in SOCIAL): return "NOISE"
    if any(e in dom for e in ESP): return "NOISE"
    if any(n in local for n in NOISE_LOCAL) and dom not in FREE:
        if any(tk in (a+" "+subj.lower()) for tk in TXN_LOCAL) or any(r in a for r in RETAIL): return "TXN"
        return "NOISE"
    if any(r in a for r in RETAIL): return "TXN"
    if any(tk in subj.lower() for tk in TXN_LOCAL) and dom not in FREE and ".edu" not in dom and ".gov" not in dom: return "TXN"
    return "PRESERVE"

def now_dt(): return datetime.now(timezone.utc)

def age_days(dstr):
    try:
        dt=email.utils.parsedate_to_datetime(dstr)
        if dt.tzinfo is None: dt=dt.replace(tzinfo=timezone.utc)
    except Exception:
        return None
    return (now_dt()-dt).days

def load_state(name):
    try:
        with open(os.path.join(STATE_DIR, f"triage-{name}.json")) as f: return json.load(f)
    except Exception: return {}

def save_state(name, st):
    if DRY: return
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(os.path.join(STATE_DIR, f"triage-{name}.json"), "w") as f: json.dump(st, f)

UID_RE=re.compile(rb"UID (\d+)")
LBL_RE=re.compile(rb"X-GM-LABELS \(([^)]*)\)")
FLG_RE=re.compile(rb"FLAGS \(([^)]*)\)")

def sweep(acct):
    name=acct["name"]
    with open(acct["secret"]) as f: pw=f.read().strip()
    M=imaplib.IMAP4_SSL("imap.gmail.com",993); M.login(acct["email"],pw)
    M.select('"[Gmail]/All Mail"', readonly=DRY)
    t,d=M.uid("SEARCH","X-GM-RAW",'"-label:Family-Friends -in:sent -in:trash"')
    uids=d[0].split() if d and d[0] else []
    st=load_state(name); seen_now=set()
    kill=[]; to_triage=[]; sen=Counter(); ntriage=0
    today=now_dt().strftime("%Y-%m-%d")
    for i in range(0,len(uids),200):
        t,fd=M.uid("FETCH",b",".join(uids[i:i+200]),
                   "(UID FLAGS X-GM-LABELS BODY.PEEK[HEADER.FIELDS (MESSAGE-ID DATE FROM SUBJECT)])")
        for it in fd:
            if not (isinstance(it,tuple) and it[1]): continue
            um=UID_RE.search(it[0])
            if not um: continue
            uid=um.group(1)
            lm=LBL_RE.search(it[0]); labels=lm.group(1).decode("utf-8","replace") if lm else ""
            fm=FLG_RE.search(it[0]); flags=fm.group(1).decode("utf-8","replace") if fm else ""
            starred="\\Starred" in flags
            kept=("keep" in labels.lower()) or ("Family-Friends" in labels)
            h={}
            for line in it[1].decode("utf-8","replace").splitlines():
                if ":" in line: k,v=line.split(":",1); h[k.strip().lower()]=v.strip()
            a=email.utils.parseaddr(h.get("from",""))[1].lower()
            if not a or a==acct["email"]: continue
            mid=h.get("message-id","").strip().strip("<>")
            b=classify(a,h.get("subject",""))
            if b=="NOISE":
                kill.append(uid); sen[a]+=1
            elif b=="TXN":
                ad=age_days(h.get("date",""))
                if ad is None or ad>TXN_MAX: kill.append(uid); sen[a]+=1
            elif b=="TRIAGE":
                if starred or kept: continue              # user saved it
                in_triage=TRIAGE_LABEL in labels
                if not in_triage: to_triage.append(uid)
                if mid:
                    seen_now.add(mid)
                    first=st.setdefault(mid, today)
                    try: age=(now_dt()-datetime.strptime(first,"%Y-%m-%d").replace(tzinfo=timezone.utc)).days
                    except Exception: age=0
                    if in_triage and age>=TRIAGE_MAX:
                        kill.append(uid); sen["[triage-expired] "+a]+=1
                ntriage+=1
    trashed=0; labeled=0
    if not DRY:
        for i in range(0,len(to_triage),300):
            if M.uid("STORE",b",".join(to_triage[i:i+300]),"+X-GM-LABELS",f'"{TRIAGE_LABEL}"')[0]=="OK":
                labeled+=len(to_triage[i:i+300])
        for i in range(0,len(kill),300):
            if M.uid("MOVE",b",".join(kill[i:i+300]),'"[Gmail]/Trash"')[0]=="OK":
                trashed+=len(kill[i:i+300])
    st={k:v for k,v in st.items() if k in seen_now}          # prune left-triage msgs
    save_state(name, st)
    M.logout()
    return {"account":name,"scanned":len(uids),"trash_target":len(kill),"trashed":trashed,
            "triage_new":len(to_triage),"triage_labeled":labeled,"in_triage":ntriage,"top":sen.most_common(6)}

def notify(results):
    if not NOTIFY: return
    mode="DRY-RUN" if DRY else "ACTIVE"
    lines=[f"mail-janitor {mode} — receipts<{TXN_MAX}d, newsletters triaged {TRIAGE_MAX}d"]
    for r in results:
        verb="would trash" if DRY else "trashed"
        lines.append(f"• {r['account']}: {verb} {r['trash_target']}, +{r['triage_new']} to triage ({r['in_triage']} in queue)")
    payload={"title":f"mail-janitor {mode}","topic":"nightly-builds","source":"mail-janitor",
             "priority":4,"body":"\n".join(lines)}
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
        print(f"{r['account']}: scanned={r['scanned']} trash_target={r['trash_target']} "
              f"trashed={r['trashed']} triage_new={r['triage_new']} in_triage={r['in_triage']}")
        for a,n in r["top"]: print(f"    {n:>4}  {a}")
    notify(results)

if __name__=="__main__":
    main()
