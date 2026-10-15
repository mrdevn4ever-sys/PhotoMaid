#!/usr/bin/env python3
"""Verify that real UI gestures reached both sides of the native ad's actual time gate."""
import datetime
import pathlib
import re
import sys


def verify(path):
    cards = []
    for line in path.read_text().splitlines():
        match = re.search(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+).*\[app\.photomaid:ads\] (native-card-[a-z-]+)$", line)
        if not match:
            continue
        instant = datetime.datetime.fromisoformat(match[1])
        event = match[2]
        if event == "native-card-presented":
            cards.append([])
        if cards:
            cards[-1].append((instant, event))
    assert len(cards) == 2, f"Expected exactly two real native cards, got {len(cards)}"
    first, second = cards
    first_events = [event for _, event in first]
    second_events = [event for _, event in second]
    assert first_events[:3] == ["native-card-presented", "native-card-swipe-wait", "native-card-swipe-down"], first_events
    # The timer may expire during the 180 ms dismissal animation, after the locked down gesture.
    assert first_events[3:] in ([], ["native-card-can-skip"]), first_events
    assert second_events == ["native-card-presented", "native-card-swipe-wait", "native-card-can-skip", "native-card-swipe-ready"], second_events
    locked_for = (second[2][0] - second[0][0]).total_seconds()
    # Unified log timestamps have millisecond precision; the production timer remains exactly 1500 ms.
    assert locked_for >= 1.49, f"Native card unlocked too early: {locked_for:.3f}s"
    print(f"PASS: down while locked; sideways blocked while locked; sideways allowed after {locked_for:.3f}s")


if __name__ == "__main__":
    verify(pathlib.Path(sys.argv[1]))
