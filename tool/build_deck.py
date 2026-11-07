"""Builds assets/deck.json from the word list, the Turkish meanings and Tatoeba.

Run from the project root: python tool/build_deck.py
Inputs live in tool/data (see README, "Kelime verisi").
"""
import bz2
import collections
import json
import re
from pathlib import Path

DATA = Path(__file__).parent / "data"
OUT = Path(__file__).parent.parent / "assets" / "deck.json"

MIN_WORDS, MAX_WORDS = 3, 10
TOKEN = re.compile(r"[a-z]+(?:'[a-z]+)?")
# Tatoeba leans heavily on these names; a little goes a long way.
NAMES = {"tom", "mary", "john", "sami", "layla", "ziri", "rima", "yanni", "skura"}
# A flash card in a daily habit is no place for these.
AVOID = re.compile(
    r"\b(rape|raped|suicide|nazi|hitler|fuck\w*|shit|bitch|nigger|slut|whore|penis|vagina|porn\w*|"
    r"kill (?:you|me|him|her|them|myself|yourself)|bastard|naked|sex\w*)\b",
    re.I,
)


def read_tsv(name):
    with bz2.open(DATA / name, "rt", encoding="utf8") as f:
        for line in f:
            yield line.rstrip("\n").split("\t")


def load_words():
    lines = (DATA / "ngsl_stats.csv").read_text(encoding="utf8").splitlines()[1:]
    return [l.split(",")[0].strip().lower() for l in lines if l.strip()]


def load_forms():
    forms = {}
    for line in (DATA / "ngsl_lemmas.csv").read_text(encoding="utf8").splitlines():
        if line.startswith("#") or not line.strip():
            continue
        parts = [p.strip().lower() for p in line.split(",") if p.strip()]
        forms.setdefault(parts[0], set()).update(parts)
    return forms


def load_meanings():
    meanings = {}
    for name in ("tr_1.txt", "tr_2.txt"):
        for line in (DATA / name).read_text(encoding="utf8").splitlines():
            if line.strip():
                word, meaning = line.split("|", 1)
                meanings[word.strip()] = meaning.strip()
    return meanings


def load_own_sentences():
    path = DATA / "own_sentences.txt"
    own = {}
    if path.exists():
        for line in path.read_text(encoding="utf8").splitlines():
            if line.strip():
                word, en, tr = line.split("|")
                own[word] = (en.strip(), tr.strip())
    return own


def load_pairs():
    tur = {r[0]: r[2] for r in read_tsv("tur.bz2")}
    eng = {r[0]: r[2] for r in read_tsv("eng.bz2")}
    seen = set()
    for a, b in read_tsv("links.bz2"):
        pair = None
        if a in tur and b in eng:
            pair = (eng[b], tur[a])
        elif a in eng and b in tur:
            pair = (eng[a], tur[b])
        if pair and pair[0] not in seen:
            seen.add(pair[0])
            yield pair


def main():
    words = load_words()
    forms = load_forms()
    meanings = load_meanings()
    own = load_own_sentences()
    missing = [w for w in words if w not in meanings]
    assert not missing, f"anlamı olmayan kelime: {missing[:20]}"

    rank = {w: i for i, w in enumerate(words)}
    form_rank = {}
    for word in words:
        for form in forms.get(word, {word}) | {word}:
            form_rank[form] = min(form_rank.get(form, 10**6), rank[word])

    # Every sentence is scored once, then offered to each word it contains.
    candidates = collections.defaultdict(list)
    for en, tr in load_pairs():
        if AVOID.search(en) or '"' in en or len(tr) > 90:
            continue
        tokens = TOKEN.findall(en.lower())
        if not MIN_WORDS <= len(tokens) <= MAX_WORDS:
            continue
        known = [form_rank.get(t) for t in tokens]
        # A sentence only helps if the learner can read the rest of it.
        unknown = known.count(None)
        for token in set(tokens):
            if token not in form_rank:
                continue
            word = words[form_rank[token]]
            others = [k for k, t in zip(known, tokens) if t != token and k is not None]
            hardest_other = max(others, default=0)
            score = (
                unknown * 3000
                + max(0, hardest_other - rank[word])
                + abs(len(tokens) - 6) * 40
                + (250 if set(tokens) & NAMES else 0)
                + (0 if token == word else 60)
            )
            candidates[word].append((score, en, tr, token))

    used = collections.Counter()
    no_sentence = []
    chosen = {}
    # The rarest words pick first so they get the sentences only they can use.
    for word in sorted(words, key=lambda w: len(candidates[w])):
        if word in own:
            en, tr = own[word]
            hits = [t for t in TOKEN.findall(en.lower()) if t == word or form_rank.get(t) == rank[word]]
            assert hits, f"kendi cümlesinde kelime yok: {word}"
            chosen[word] = (en, tr, hits[0])
            continue
        ranked = sorted(candidates[word], key=lambda c: c[0] + used[c[1]] * 500)
        if not ranked:
            no_sentence.append(word)
            continue
        _, en, tr, token = ranked[0]
        used[en] += 1
        chosen[word] = (en, tr, token)

    deck = []
    for word in words:
        en, tr, token = chosen[word]
        deck.append({"w": word, "t": meanings[word], "e": en, "s": tr, "f": token})

    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps(deck, ensure_ascii=False, separators=(",", ":")), encoding="utf8")
    print(f"{len(deck)} kelime, {OUT.stat().st_size // 1024} KB")
    print("cumlesiz:", len(no_sentence), " ".join(no_sentence))
    weak = [w for w in words if w not in own and sum(1 for c in candidates[w] if c[0] < 3000) == 0]
    print("zayif:", len(weak), " ".join(weak))


if __name__ == "__main__":
    main()
