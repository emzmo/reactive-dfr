#!/usr/bin/env python3
"""feeder.py — rotating info feeder for the Touch Bar screensaver.

Reads feeder_config.toml, fetches data from enabled modules (RSS news,
crypto prices, calendar, mail), and outputs one item at a time as JSON
for the reactive-dfr Command widget.

State is kept in /tmp/reactive_dfr_feeder_state.txt (an integer that
increments on each call). Data is cached in ~/.cache/reactive_dfr_feeder/
for 10 minutes to avoid hammering APIs.

On each call, the feeder advances to the next item across all enabled
modules. When it reaches the end, it wraps around.

OnClick actions are written to /tmp/reactive_dfr_feeder_action.txt
so the ScreensaverLayer's OnClick can execute them.
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

# Paths
CONFIG_PATH = Path.home() / ".config" / "reactive-dfr" / "feeder_config.toml"
STATE_PATH = Path(os.environ.get("CACHE_DIRECTORY", "/var/cache/reactive-dfr")) / "feeder_state.txt"
ACTION_PATH = Path(os.environ.get("CACHE_DIRECTORY", "/var/cache/reactive-dfr")) / "feeder_action.txt"
CACHE_DIR = Path(os.environ.get("CACHE_DIRECTORY", "/var/cache/reactive-dfr")) / "feeder_cache"
CACHE_TTL = 600  # 10 minutes

# CoinGecko coin ID mapping (universal symbol -> CG API id)
COINGECKO_IDS = {
    "BTC": "bitcoin",
    "ETH": "ethereum",
    "SOL": "solana",
    "ADA": "cardano",
    "DOT": "polkadot",
    "XRP": "ripple",
    "DOGE": "dogecoin",
    "AVAX": "avalanche-2",
    "MATIC": "matic-network",
    "LINK": "chainlink",
}


def load_config():
    """Load the TOML config, falling back to an empty config."""
    try:
        import tomllib
        with open(CONFIG_PATH, "rb") as f:
            return tomllib.load(f)
    except (FileNotFoundError, ImportError):
        try:
            import tomli
            with open(CONFIG_PATH, "rb") as f:
                return tomli.load(f)
        except (FileNotFoundError, ImportError):
            return {}


def read_state():
    """Read the rotation counter, starting at 0."""
    try:
        return int(STATE_PATH.read_text().strip())
    except (FileNotFoundError, ValueError):
        return 0


def write_state(n):
    STATE_PATH.write_text(str(n))


def write_action(cmd):
    ACTION_PATH.write_text(cmd)


def cache_path(name):
    return CACHE_DIR / f"{name}.json"


def load_cache(name):
    """Load cached data if fresh (< CACHE_TTL seconds old)."""
    p = cache_path(name)
    if not p.exists():
        return None
    age = time.time() - p.stat().st_mtime
    if age > CACHE_TTL:
        return None
    try:
        return json.loads(p.read_text())
    except (json.JSONDecodeError, OSError):
        return None


def save_cache(name, data):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_path(name).write_text(json.dumps(data))


# ---------------------------------------------------------------------------
# Module: News (RSS)
# ---------------------------------------------------------------------------

def fetch_news(config):
    """Fetch RSS feeds and return a list of {text, action} items."""
    cache = load_cache("news")
    if cache is not None:
        return cache

    items = []
    try:
        import feedparser
    except ImportError:
        return [{"text": "Install feedparser", "action": "true"}]

    for source in config.get("sources", []):
        url = source.get("url", "")
        count = source.get("count", 3)
        prefix = source.get("prefix", "")
        try:
            feed = feedparser.parse(url)
            for entry in feed.entries[:count]:
                title = entry.get("title", "").strip()
                link = entry.get("link", "")
                if title:
                    # Truncate to fit the Touch Bar
                    if len(title) > 60:
                        title = title[:57] + "..."
                    items.append({
                        "text": f"{prefix} {title}",
                        "action": f"xdg-open '{link}'" if link else "true",
                    })
        except Exception:
            continue

    save_cache("news", items)
    return items


# ---------------------------------------------------------------------------
# Module: Crypto (CoinGecko)
# ---------------------------------------------------------------------------

def fetch_crypto(config):
    """Fetch crypto prices from CoinGecko and return items."""
    cache = load_cache("crypto")
    if cache is not None:
        return cache

    coins = config.get("coins", [])
    prefix = config.get("prefix", "")
    items = []

    if not coins:
        return items

    try:
        import urllib.request
        # Build comma-separated list of CoinGecko IDs
        cg_ids = []
        sym_map = {}
        for sym in coins:
            cg_id = COINGECKO_IDS.get(sym.upper(), sym.lower())
            cg_ids.append(cg_id)
            sym_map[cg_id] = sym.upper()

        url = (
            "https://api.coingecko.com/api/v3/simple/price"
            f"?ids={','.join(cg_ids)}&vs_currencies=usd&include_24hr_change=true"
        )
        req = urllib.request.Request(url, headers={"User-Agent": "reactive-dfr/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())

        for cg_id in cg_ids:
            sym = sym_map[cg_id]
            info = data.get(cg_id, {})
            price = info.get("usd", 0)
            change = info.get("usd_24h_change", 0)
            arrow = "+" if change >= 0 else ""
            if price >= 1000:
                price_str = f"${price:,.0f}"
            elif price >= 1:
                price_str = f"${price:.2f}"
            else:
                price_str = f"${price:.4f}"
            items.append({
                "text": f"{prefix}{sym} {price_str} {arrow}{change:.1f}%",
                "action": f"xdg-open 'https://www.coingecko.com/en/coins/{cg_id}'",
            })
    except Exception:
        items.append({"text": "Crypto n/a", "action": "true"})

    save_cache("crypto", items)
    return items


# ---------------------------------------------------------------------------
# Module: Calendar (khal)
# ---------------------------------------------------------------------------

def fetch_calendar(config):
    """Read today's events via khal."""
    cache = load_cache("calendar")
    if cache is not None:
        return cache

    app_cmd = config.get("app_cmd", "thunderbird")
    items = []

    try:
        result = subprocess.run(
            ["khal", "list", "now", "24h"],
            capture_output=True, text=True, timeout=5,
        )
        lines = [l.strip() for l in result.stdout.splitlines() if l.strip()]
        for line in lines[:5]:
            if len(line) > 60:
                line = line[:57] + "..."
            items.append({
                "text": f"📅 {line}",
                "action": app_cmd,
            })
    except (FileNotFoundError, subprocess.SubprocessError):
        pass

    if not items:
        items.append({"text": "📅 No events today", "action": app_cmd})

    # Calendar cache TTL is shorter (5 min) since events can change
    p = cache_path("calendar")
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(items))

    save_cache("calendar", items)
    return items


# ---------------------------------------------------------------------------
# Module: Mail (placeholder)
# ---------------------------------------------------------------------------

def fetch_mail(config):
    """Show a mail reminder."""
    app_cmd = config.get("app_cmd", "thunderbird")
    return [{"text": "✉️ Check Mail", "action": app_cmd}]


# ---------------------------------------------------------------------------
# Main: rotate through all enabled modules
# ---------------------------------------------------------------------------

def main():
    config = load_config()

    # Collect all items from enabled modules, in config order.
    all_items = []

    news_cfg = config.get("news", {})
    if news_cfg.get("enabled"):
        all_items.extend(fetch_news(news_cfg))

    crypto_cfg = config.get("crypto", {})
    if crypto_cfg.get("enabled"):
        all_items.extend(fetch_crypto(crypto_cfg))

    cal_cfg = config.get("calendar", {})
    if cal_cfg.get("enabled"):
        all_items.extend(fetch_calendar(cal_cfg))

    mail_cfg = config.get("mail", {})
    if mail_cfg.get("enabled"):
        all_items.extend(fetch_mail(mail_cfg))

    if not all_items:
        # Fallback: show a simple clock
        import datetime
        now = datetime.datetime.now()
        text = now.strftime("%H:%M  %a %d %b")
        print(json.dumps({"text": text, "icon": "schedule"}))
        write_action("true")
        return

    # Rotate: advance the counter and wrap around.
    state = read_state()
    idx = state % len(all_items)
    write_state(state + 1)

    item = all_items[idx]
    text = item.get("text", "")
    action = item.get("action", "true")

    # Output JSON for the reactive-dfr Command widget.
    print(json.dumps({"text": text}))

    # Write the OnClick action so the ScreensaverLayer can execute it.
    write_action(action)


if __name__ == "__main__":
    main()