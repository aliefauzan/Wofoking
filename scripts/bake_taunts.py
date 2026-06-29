#!/usr/bin/env python3
"""
Bake PhraseBank taunts into ElevenLabs mp3 clips for Wofoking — Load Away.

One-time generation. Output files are named "<lang>_<slug>.mp3" where slug()
MUST stay byte-for-byte identical to VoiceService.slug(_:) in Swift, or the app
won't find the clip and will fall back to AVSpeechSynthesizer.

Usage:
    export ELEVENLABS_API_KEY=sk_...
    export ELEVENLABS_VOICE_ID=<voice id>      # pick a smug/condescending voice
    python3 bake_taunts.py --out ../Wofoking/Taunts

Then in Xcode, drag the "Taunts" folder into the Wofoking iOS target (it lives
under the synced root group, so it auto-adds as a bundle resource). The app
loads clips with Bundle.main.url(forResource:..., withExtension:"mp3").

Free tier note: ElevenLabs free is non-commercial + requires attribution. For an
App Store build, run this once on a paid Starter plan (~$5/mo, commercial
license), then you can cancel — the mp3s ship in the bundle, no runtime API.
"""

import argparse
import os
import sys
import urllib.request

# Mirror of PhraseBank.bank (English). Keep in sync if the Swift bank changes.
LINES_EN = [
    # earlyLookBack
    "Too early. Classic.",
    "You looked too soon.",
    "The loading bar saw you.",
    "99% confidence. 0% patience.",
    "You blinked. It noticed.",
    # fail
    "Almost. But almost is still failure.",
    "You were one second away from greatness.",
    "The loading bar is disappointed, but not surprised.",
    "Try again. The loading bar enjoys this.",
    # win
    "Fine. You win. This time.",
    "The loading bar concedes. Barely.",
    "Loading complete. Joy not included.",
    # inviteLookBack
    "Go on, look. I dare you.",
    "Don't you want to see the progress?",
    "It's almost done. Come check.",
    # betrayalLookBack
    "You trusted the loading bar. Mistake.",
    "It moved. You didn't.",
    "You and patience are clearly not friends.",
    # penalty
    "Because you didn't trust me, I'll decrease it back.",
    "100% was there. You were not.",
    "Watch it fall. You earned this.",
    # level3Tap
    "Still loading.",
    "Come back later.",
    "Level 3 is preparing itself emotionally.",
    "99%. Forever.",
    "This level is not ready to be perceived.",
    # deletePrank
    "You think you can run from us?",
    # gaveUp
    "Giving up? The loading bar expected nothing less.",
    "Quitter. The bar will remember this.",
    "You looked too long and lost your nerve. Typical.",
    "Surrender accepted. Disappointment noted.",
    # fakeOut
    "99%! …just kidding.",
    "Oops. Butterfingers. Back you go.",
    "You really thought that was it?",
    "So close. So very fake.",
    "Loading complete! …loading not complete.",
    # peek
    "I saw that. Eyes front, cheater.",
    "Peeking? Bold. Punished.",
    "Your eyes betray you.",
    "Turn the head, not just the pretend.",
    "Nice try, sneak. Minus points.",
    # heartRateSpike
    "Relax. It's a loading bar.",
    "Your heart is racing. Delicious.",
    "Calm down. Or don't. I love this.",
    "That pulse says you care too much.",
    # frustrated
    "I can see that frown.",
    "Aw, are you mad?",
    "That scowl won't load the bar.",
    "Anger detected. Anger ignored.",
    "Unclench. It's just a game. Mostly.",
]


def slug(text: str) -> str:
    """Must match VoiceService.slug(_:) in Swift exactly."""
    out = []
    last_was_sep = False
    for ch in text.lower():
        if ch.isascii() and ch.isalnum():
            out.append(ch)
            last_was_sep = False
        elif not last_was_sep:
            out.append("_")
            last_was_sep = True
    return "".join(out).strip("_")


def synth(text: str, api_key: str, voice_id: str) -> bytes:
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
    body = (
        '{"text": %s, "model_id": "eleven_multilingual_v2", '
        '"voice_settings": {"stability": 0.35, "similarity_boost": 0.8, "style": 0.6}}'
        % _json_str(text)
    ).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("xi-api-key", api_key)
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "audio/mpeg")
    with urllib.request.urlopen(req) as resp:
        return resp.read()


def _json_str(s: str) -> str:
    import json
    return json.dumps(s, ensure_ascii=False)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="../Wofoking/Taunts", help="output folder")
    ap.add_argument("--lang", default="en", help="language code prefix (en/id)")
    ap.add_argument("--force", action="store_true", help="re-generate existing clips")
    args = ap.parse_args()

    api_key = os.environ.get("ELEVENLABS_API_KEY")
    voice_id = os.environ.get("ELEVENLABS_VOICE_ID")
    if not api_key or not voice_id:
        print("Set ELEVENLABS_API_KEY and ELEVENLABS_VOICE_ID.", file=sys.stderr)
        return 1

    os.makedirs(args.out, exist_ok=True)
    lines = LINES_EN  # add an LINES_ID list + select on args.lang for Indonesian

    for line in lines:
        name = f"{args.lang}_{slug(line)}.mp3"
        path = os.path.join(args.out, name)
        if os.path.exists(path) and not args.force:
            print(f"skip  {name}")
            continue
        try:
            data = synth(line, api_key, voice_id)
        except Exception as e:  # noqa: BLE001
            print(f"FAIL  {name}: {e}", file=sys.stderr)
            continue
        with open(path, "wb") as f:
            f.write(data)
        print(f"baked {name}  ({len(data)} bytes)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
