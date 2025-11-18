#!/usr/bin/env python3
import argparse
import base64
import os
import re
import requests
import sys
from email.mime.text import MIMEText
from urllib.parse import parse_qs

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

SCOPES = [
  "https://www.googleapis.com/auth/gmail.modify",
  "https://www.googleapis.com/auth/gmail.send",
  "https://www.googleapis.com/auth/gmail.readonly"
]

def auth():
    creds = None
    if os.path.exists("token.json"):
        creds = Credentials.from_authorized_user_file("token.json", SCOPES)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file("credentials.json", SCOPES)
            creds = flow.run_local_server(port=0)
        with open("token.json", "w") as f:
            f.write(creds.to_json())
    service = build("gmail", "v1", credentials=creds)
    return service

def list_message_ids(service, query, max_results=500):
    ids = []
    request = service.users().messages().list(userId="me", q=query, maxResults=500)
    while request:
        resp = request.execute()
        if "messages" in resp:
            ids.extend([m["id"] for m in resp["messages"]])
        request = service.users().messages().list_next(request, resp)
        if len(ids) >= max_results:
            break
    return ids

def get_message(service, mid):
    return service.users().messages().get(userId="me", id=mid, format="full").execute()

def get_header(headers, name):
    for h in headers:
        if h["name"].lower() == name.lower():
            return h["value"]
    return None

def extract_links_from_header(value):
    if not value:
        return [], []
    mailtos = re.findall(r"<mailto:[^>]+>", value)
    urls = re.findall(r"<https?://[^>]+>", value)
    mailtos = [m[1:-1] for m in mailtos]
    urls = [u[1:-1] for u in urls]
    return mailtos, urls

def extract_links_from_html(html):
    results = []
    for m in re.finditer(r"<a[^>]+href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>", html, flags=re.I|re.S):
        href = m.group(1)
        text = m.group(2)
        if "unsubscribe" in href.lower() or "unsubscribe" in text.lower():
            results.append(href)
    return results

def get_html_parts(payload):
    if payload.get("mimeType", "") == "text/html":
        data = payload.get("body", {}).get("data")
        if data:
            return [base64.urlsafe_b64decode(data.encode("utf-8")).decode("utf-8", errors="ignore")]
        return []
    parts = []
    for p in payload.get("parts", []) or []:
        parts.extend(get_html_parts(p))
    return parts

def parse_mailto(link):
    link = link[len("mailto:"):] if link.lower().startswith("mailto:") else link
    parts = link.split("?", 1)
    addr = parts[0]
    q = {}
    if len(parts) > 1:
        q = {k:v[0] for k,v in parse_qs(parts[1]).items()}
    return addr, q

def send_unsubscribe_mail(service, to_addr, subject=None):
    msg = MIMEText("")
    msg["to"] = to_addr
    msg["from"] = "me"
    msg["subject"] = subject or "Unsubscribe"
    raw = base64.urlsafe_b64encode(msg.as_bytes()).decode()
    body = {"raw": raw}
    return service.users().messages().send(userId="me", body=body).execute()

def try_unsubscribe_http(url):
    try:
        r = requests.get(url, timeout=15, headers={"User-Agent":"Mozilla/5.0"})
        if r.status_code in (200, 202, 204, 301, 302):
            return True, f"GET {r.status_code}"
        r = requests.post(url, timeout=15, headers={"User-Agent":"Mozilla/5.0"})
        if r.status_code in (200,202,204,301,302):
            return True, f"POST {r.status_code}"
        return False, f"{r.status_code}"
    except Exception as e:
        return False, str(e)

def find_unsubscribe_targets(service, msg):
    headers = msg["payload"].get("headers", [])
    lu = get_header(headers, "List-Unsubscribe")
    mailtos = []
    urls = []
    if lu:
        mt, u = extract_links_from_header(lu)
        mailtos.extend(mt)
        urls.extend(u)
    htmls = get_html_parts(msg["payload"])
    for h in htmls:
        found = extract_links_from_html(h)
        for f in found:
            if f.startswith("mailto:"):
                mailtos.append(f)
            elif f.startswith("http"):
                urls.append(f)
    return list(dict.fromkeys(mailtos)), list(dict.fromkeys(urls))

def archive_message(service, mid, delete=False, dry_run=False):
    if dry_run:
        return True
    if delete:
        try:
            service.users().messages().delete(userId="me", id=mid).execute()
            return True
        except Exception:
            return False
    else:
        try:
            service.users().messages().modify(userId="me", id=mid, body={"removeLabelIds":["INBOX"]}).execute()
            return True
        except Exception:
            return False

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--query", default="category:promotions in:inbox")
    parser.add_argument("--delete", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--max", type=int, default=10000)
    args = parser.parse_args()
    if not os.path.exists("credentials.json"):
        print("credentials.json not found. Create OAuth desktop credentials and save as credentials.json")
        sys.exit(1)
    service = auth()
    ids = list_message_ids(service, args.query, max_results=args.max)
    total = len(ids)
    print(f"Found {total} messages for query: {args.query}")
    unsub_count = 0
    archive_count = 0
    failed_unsub = []
    for i, mid in enumerate(ids, 1):
        try:
            msg = get_message(service, mid)
            mailtos, urls = find_unsubscribe_targets(service, msg)
            unsubbed = False
            for mlink in mailtos:
                addr, q = parse_mailto(mlink)
                subj = q.get("subject") or "Unsubscribe"
                if args.dry_run:
                    print(f"[DRY] Would send unsubscribe email to {addr} subject={subj}")
                    unsubbed = True
                else:
                    try:
                        send_unsubscribe_mail(service, addr, subj)
                        unsubbed = True
                    except Exception as e:
                        failed_unsub.append((mid, "mailto", addr, str(e)))
            for url in urls:
                if args.dry_run:
                    print(f"[DRY] Would GET/POST unsubscribe url {url}")
                    unsubbed = True
                else:
                    ok, info = try_unsubscribe_http(url)
                    if ok:
                        unsubbed = True
                    else:
                        failed_unsub.append((mid, "http", url, info))
            if unsubbed:
                unsub_count += 1
            archived = archive_message(service, mid, delete=args.delete, dry_run=args.dry_run)
            if archived:
                archive_count += 1
            if i % 50 == 0:
                print(f"Processed {i}/{total} messages")
        except Exception as e:
            failed_unsub.append((mid, "error", "", str(e)))
            continue
    print("Summary")
    print(f"Messages found: {total}")
    print(f"Unsubscribe attempts: {unsub_count}")
    print(f"Archived/deleted: {archive_count}")
    if failed_unsub:
        print("Failures:")
        for f in failed_unsub[:50]:
            print(f)
    if args.dry_run:
        print("Dry run complete. No messages modified.")

if __name__ == "__main__":
    main()
