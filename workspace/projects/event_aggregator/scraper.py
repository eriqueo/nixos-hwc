#!/usr/bin/env python3
"""
Bozeman Weekend Events Scraper
Outputs a JSON array of events for consumption by n8n.
Usage:
  python3 scraper.py           # prints human-readable digest
  python3 scraper.py --json    # prints JSON array for n8n
"""

import sys
import os
import re
import json
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

import requests
from bs4 import BeautifulSoup

try:
    from icalendar import Calendar
    ICAL_AVAILABLE = True
except ImportError:
    ICAL_AVAILABLE = False

MT = ZoneInfo("America/Denver")

def get_weekend_dates():
    today = date.today()
    days_until_saturday = (5 - today.weekday()) % 7
    if days_until_saturday == 0:
        days_until_saturday = 7
    saturday = today + timedelta(days=days_until_saturday)
    sunday = saturday + timedelta(days=1)
    return saturday, sunday

SATURDAY, SUNDAY = get_weekend_dates()
TARGET_DATES = {SATURDAY, SUNDAY}

BUSINESS_KEYWORDS = [
    'remodel', 'remodeling', 'contractor', 'construction', 'build', 'builder',
    'business', 'networking', 'chamber', 'prospera', 'swmbia', 'meetup',
    'entrepreneur', 'startup', 'workshop', 'seminar', 'conference', 'trade',
    'professional', 'industry', 'association', 'member', 'leadership',
    'finance', 'marketing', 'sales', 'real estate', 'property', 'housing',
    'permit', 'code', 'inspection', 'subcontractor', 'hvac', 'plumbing',
    'electrical', 'roofing', 'flooring', 'tile', 'cabinet', 'design build',
    'home improvement', 'renovation', 'restoration', 'development',
]

def classify_event(title, venue='', source=''):
    text = f"{title} {venue} {source}".lower()
    if source in ('SWMBIA', 'Prospera', 'Chamber'):
        return 'business'
    for kw in BUSINESS_KEYWORDS:
        if kw in text:
            return 'business'
    return 'family'

HEADERS = {
    'User-Agent': (
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    )
}

def safe_get(url, timeout=10):
    try:
        r = requests.get(url, headers=HEADERS, timeout=timeout)
        r.raise_for_status()
        return r
    except Exception as e:
        print(f"[WARN] GET {url} failed: {e}", file=sys.stderr)
        return None

def parse_ical_date(dt_val):
    if dt_val is None:
        return None
    if hasattr(dt_val, 'dt'):
        dt_val = dt_val.dt
    if isinstance(dt_val, datetime):
        if dt_val.tzinfo:
            dt_val = dt_val.astimezone(MT)
        return dt_val.date()
    if isinstance(dt_val, date):
        return dt_val
    return None

def parse_ical_time(dt_val):
    if dt_val is None:
        return ''
    if hasattr(dt_val, 'dt'):
        dt_val = dt_val.dt
    if isinstance(dt_val, datetime):
        if dt_val.tzinfo:
            dt_val = dt_val.astimezone(MT)
        return dt_val.strftime('%-I:%M %p')
    return ''

def parse_ical_datetime_iso(dt_val):
    """Return ISO 8601 string for use in .ics generation, or None."""
    if dt_val is None:
        return None
    if hasattr(dt_val, 'dt'):
        dt_val = dt_val.dt
    if isinstance(dt_val, datetime):
        if dt_val.tzinfo:
            dt_val = dt_val.astimezone(MT)
        return dt_val.strftime('%Y%m%dT%H%M%S')
    if isinstance(dt_val, date):
        return dt_val.strftime('%Y%m%d')
    return None

def scrape_ical(url, source_name, default_category='family'):
    events = []
    if not ICAL_AVAILABLE:
        return events
    r = safe_get(url)
    if not r:
        return events
    try:
        cal = Calendar.from_ical(r.content)
    except Exception as e:
        print(f"[WARN] Failed to parse iCal from {source_name}: {e}", file=sys.stderr)
        return events

    for component in cal.walk():
        if component.name != 'VEVENT':
            continue
        try:
            dtstart = component.get('DTSTART')
            dtend = component.get('DTEND')
            event_date = parse_ical_date(dtstart)
            if event_date not in TARGET_DATES:
                continue
            time_str = parse_ical_time(dtstart)
            dtstart_iso = parse_ical_datetime_iso(dtstart)
            dtend_iso = parse_ical_datetime_iso(dtend) if dtend else None
            # If no end time, default to 1 hour after start
            if not dtend_iso and dtstart_iso:
                if 'T' in dtstart_iso:
                    try:
                        dt = datetime.strptime(dtstart_iso, '%Y%m%dT%H%M%S')
                        dtend_iso = (dt + timedelta(hours=1)).strftime('%Y%m%dT%H%M%S')
                    except Exception:
                        dtend_iso = dtstart_iso
                else:
                    dtend_iso = dtstart_iso
            title = str(component.get('SUMMARY', 'Untitled Event')).strip()
            location = str(component.get('LOCATION', '')).strip()
            url_val = str(component.get('URL', '')).strip()
            description = str(component.get('DESCRIPTION', '')).strip()
            parts = [p.strip() for p in location.split(',', 1)]
            venue = parts[0] if parts else ''
            address = parts[1] if len(parts) > 1 else location
            category = classify_event(title, venue, source_name)
            events.append({
                'title': title,
                'date': event_date.isoformat(),
                'time_str': time_str,
                'dtstart_iso': dtstart_iso,
                'dtend_iso': dtend_iso,
                'venue': venue,
                'address': address,
                'url': url_val,
                'description': description[:500] if description else '',
                'source': source_name,
                'category': category,
            })
        except Exception as e:
            print(f"[WARN] Error parsing event from {source_name}: {e}", file=sys.stderr)
    print(f"[INFO] {source_name}: {len(events)} events found", file=sys.stderr)
    return events

def scrape_bozone():
    events = []
    for target_date in sorted(TARGET_DATES):
        url = f"https://www.bozone.com/events/{target_date}/?ical=1"
        print(f"[INFO] Fetching BoZone iCal: {url}", file=sys.stderr)
        day_events = scrape_ical(url, 'BoZone', default_category='family')
        events.extend(day_events)
    return events

MEETUP_ICAL_URLS = [
    "https://www.meetup.com/bozeman-entrepreneurs/events/ical/",
    "https://www.meetup.com/bozeman-tech/events/ical/",
    "https://www.meetup.com/bozeman-startup-week/events/ical/",
]

def scrape_meetup():
    events = []
    for url in MEETUP_ICAL_URLS:
        group = url.split('/')[4] if len(url.split('/')) > 4 else 'Meetup'
        print(f"[INFO] Fetching Meetup iCal: {url}", file=sys.stderr)
        day_events = scrape_ical(url, f'Meetup/{group}', default_category='business')
        events.extend(day_events)
    return events

def scrape_eventbrite():
    events = []
    for target_date in sorted(TARGET_DATES):
        date_str = target_date.strftime('%Y-%m-%d')
        url = (
            f"https://www.eventbrite.com/d/mt--bozeman/events/"
            f"?start_date={date_str}&end_date={date_str}"
        )
        print(f"[INFO] Fetching Eventbrite: {url}", file=sys.stderr)
        r = safe_get(url)
        if not r:
            continue
        soup = BeautifulSoup(r.text, 'lxml')
        scripts = soup.find_all('script', type='application/ld+json')
        for script in scripts:
            try:
                data = json.loads(script.string or '{}')
                items = data if isinstance(data, list) else [data]
                for item in items:
                    if item.get('@type') not in ('Event', 'SocialEvent', 'EducationEvent'):
                        continue
                    start_raw = item.get('startDate', '')
                    end_raw = item.get('endDate', '')
                    try:
                        if 'T' in start_raw:
                            dt = datetime.fromisoformat(start_raw.replace('Z', '+00:00'))
                            dt = dt.astimezone(MT)
                            event_date = dt.date()
                            time_str = dt.strftime('%-I:%M %p')
                            dtstart_iso = dt.strftime('%Y%m%dT%H%M%S')
                        else:
                            event_date = date.fromisoformat(start_raw[:10])
                            time_str = ''
                            dtstart_iso = event_date.strftime('%Y%m%d')
                        if end_raw and 'T' in end_raw:
                            dt_end = datetime.fromisoformat(end_raw.replace('Z', '+00:00')).astimezone(MT)
                            dtend_iso = dt_end.strftime('%Y%m%dT%H%M%S')
                        else:
                            dtend_iso = dtstart_iso
                    except Exception:
                        continue
                    if event_date != target_date:
                        continue
                    title = item.get('name', 'Untitled').strip()
                    loc = item.get('location', {})
                    venue = loc.get('name', '') if isinstance(loc, dict) else ''
                    addr_obj = loc.get('address', {}) if isinstance(loc, dict) else {}
                    if isinstance(addr_obj, dict):
                        address = ', '.join(filter(None, [
                            addr_obj.get('streetAddress', ''),
                            addr_obj.get('addressLocality', ''),
                            addr_obj.get('addressRegion', ''),
                        ]))
                    else:
                        address = str(addr_obj)
                    event_url = item.get('url', '')
                    category = classify_event(title, venue, 'Eventbrite')
                    events.append({
                        'title': title,
                        'date': event_date.isoformat(),
                        'time_str': time_str,
                        'dtstart_iso': dtstart_iso,
                        'dtend_iso': dtend_iso,
                        'venue': venue,
                        'address': address,
                        'url': event_url,
                        'description': item.get('description', '')[:500],
                        'source': 'Eventbrite',
                        'category': category,
                    })
            except Exception:
                pass
    seen = set()
    unique = []
    for e in events:
        key = (e['title'].lower(), e['date'])
        if key not in seen:
            seen.add(key)
            unique.append(e)
    print(f"[INFO] Eventbrite: {len(unique)} events found", file=sys.stderr)
    return unique

def scrape_html_source(url, source_name, category_override=None):
    """Generic HTML scraper using JSON-LD with tribe_events fallback."""
    events = []
    print(f"[INFO] Fetching {source_name}: {url}", file=sys.stderr)
    r = safe_get(url)
    if not r:
        return events
    soup = BeautifulSoup(r.text, 'lxml')
    for script in soup.find_all('script', type='application/ld+json'):
        try:
            data = json.loads(script.string or '{}')
            items = data if isinstance(data, list) else [data]
            for item in items:
                if item.get('@type') not in ('Event', 'SocialEvent', 'EducationEvent'):
                    continue
                start_raw = item.get('startDate', '')
                try:
                    if 'T' in start_raw:
                        dt = datetime.fromisoformat(start_raw.replace('Z', '+00:00'))
                        dt = dt.astimezone(MT)
                        event_date = dt.date()
                        time_str = dt.strftime('%-I:%M %p')
                        dtstart_iso = dt.strftime('%Y%m%dT%H%M%S')
                    else:
                        event_date = date.fromisoformat(start_raw[:10])
                        time_str = ''
                        dtstart_iso = event_date.strftime('%Y%m%d')
                except Exception:
                    continue
                if event_date not in TARGET_DATES:
                    continue
                title = item.get('name', '').strip()
                loc = item.get('location', {})
                venue = loc.get('name', source_name) if isinstance(loc, dict) else source_name
                addr_obj = loc.get('address', {}) if isinstance(loc, dict) else {}
                address = addr_obj.get('streetAddress', 'Bozeman, MT') if isinstance(addr_obj, dict) else 'Bozeman, MT'
                event_url = item.get('url', url)
                cat = category_override or classify_event(title, venue, source_name)
                events.append({
                    'title': title,
                    'date': event_date.isoformat(),
                    'time_str': time_str,
                    'dtstart_iso': dtstart_iso,
                    'dtend_iso': dtstart_iso,
                    'venue': venue,
                    'address': address,
                    'url': event_url,
                    'description': '',
                    'source': source_name,
                    'category': cat,
                })
        except Exception:
            pass
    print(f"[INFO] {source_name}: {len(events)} events found", file=sys.stderr)
    return events

def gather_all_events():
    all_events = []
    all_events.extend(scrape_bozone())
    all_events.extend(scrape_meetup())
    all_events.extend(scrape_eventbrite())
    all_events.extend(scrape_html_source("https://www.swmbia.org/events/", "SWMBIA", "business"))
    all_events.extend(scrape_html_source("https://www.bozemanchamber.com/events/", "Chamber", "business"))
    all_events.extend(scrape_html_source("https://prosperamontana.com/events/", "Prospera", "business"))
    all_events.extend(scrape_html_source("https://www.bozemanlibrary.org/events", "BPL", "family"))

    seen = set()
    unique = []
    for e in all_events:
        key = (e['title'].lower().strip(), e['date'])
        if key not in seen:
            seen.add(key)
            unique.append(e)

    print(f"[INFO] Total unique events: {len(unique)}", file=sys.stderr)
    return unique

if __name__ == '__main__':
    events = gather_all_events()

    if '--json' in sys.argv:
        # Output clean JSON array to stdout for n8n consumption
        print(json.dumps({"events": events, "saturday": SATURDAY.isoformat(), "sunday": SUNDAY.isoformat()}))
    else:
        # Human-readable summary
        print(f"\nFound {len(events)} events for {SATURDAY} – {SUNDAY}")
        for e in sorted(events, key=lambda x: (x['date'], x['time_str'] or 'ZZ')):
            print(f"  [{e['category'].upper()}] {e['date']} {e['time_str']:8} | {e['title']} ({e['source']})")
