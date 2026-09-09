"""Task 4.0k / ADR-023: research-only Qwen byte-BPE JSON constraints.

This narrows the existing envelope to the frozen one/two-paragraph screen.
It never supplies text, assigns sources, repairs output, or proves facts.
"""

from __future__ import annotations

import codecs
import hashlib
import math
import time
from uuid import UUID

import regex


MATCH_TIMEOUT_SECONDS = 0.05


class NoAllowedToken(ValueError):
    """No finite candidate can extend the current grammar prefix."""


class EnvelopeGrammar:
    def __init__(self, allowed_ids):
        identities = sorted(set(allowed_ids))
        if not 1 <= len(identities) <= 4:
            raise ValueError("grammar requires one to four source identities")
        for identity in identities:
            if not isinstance(identity, str) or str(UUID(identity)) != identity.lower():
                raise ValueError("grammar source identity must be a hyphenated UUID")
        ws = rb'[ \t\r\n]*'
        # Escaped UTF-16 surrogate code units must form a complete pair.
        scalar = rb'\\u(?:[0-9A-Ca-cE-Fe-f][0-9A-Fa-f]{3}|[dD][0-7][0-9A-Fa-f]{2})'
        pair = rb'\\u[dD][89ABab][0-9A-Fa-f]{2}\\u[dD][C-Fc-f][0-9A-Fa-f]{2}'
        text = rb'"(?:[^\x00-\x1f"\\]|\\["\\/bfnrt]|' + scalar + b'|' + pair + rb')+"'
        identity = b'(?:' + b'|'.join(regex.escape(value.encode('ascii')) for value in identities) + b')'
        reference = b'"' + identity + b'"'
        references = (rb'\[' + ws + b'(?:' + reference + b'(?:' + ws + b',' + ws + reference
                      + rb'){0,3}' + ws + rb')?\]')
        paragraph = (rb'\{' + ws + rb'"text"' + ws + b':' + ws + text + ws + b',' + ws
                     + rb'"sourceMemoryIDs"' + ws + b':' + ws + references + ws + rb'\}')
        self.pattern = (ws + rb'\{' + ws + rb'"schemaVersion"' + ws + b':' + ws + b'1' + ws + b',' + ws
                        + rb'"paragraphs"' + ws + b':' + ws + rb'\[' + ws + paragraph
                        + b'(?:' + ws + b',' + ws + paragraph + b')?' + ws + rb'\]' + ws + rb'\}' + ws)
        self.compiled = regex.compile(self.pattern)
        self.sha256 = hashlib.sha256(self.pattern).hexdigest()

    def status(self, candidate: bytes) -> str:
        if len(candidate) > 262144:
            return "invalid"
        decoder = codecs.getincrementaldecoder("utf-8")("strict")
        try:
            decoder.decode(candidate, final=False)
        except UnicodeDecodeError:
            return "invalid"
        match = self.compiled.fullmatch(candidate, partial=True, timeout=MATCH_TIMEOUT_SECONDS)
        if match is None:
            return "invalid"
        return "prefix" if match.partial or decoder.getstate()[0] else "complete"


def byte_bpe_tokens(document: dict) -> dict[int, bytes]:
    """Invert ByteLevel's reversible byte alphabet, never decode token fragments."""
    model = document.get("model", {})
    if (model.get("type") != "BPE" or document.get("decoder", {}).get("type") != "ByteLevel"
            or model.get("byte_fallback") or model.get("continuing_subword_prefix")
            or model.get("end_of_word_suffix")):
        raise ValueError("only plain Qwen ByteLevel BPE tokenizers are supported")
    visible = list(range(33, 127)) + list(range(161, 173)) + list(range(174, 256))
    alphabet = {chr(value): value for value in visible}
    for offset, value in enumerate(value for value in range(256) if value not in visible):
        alphabet[chr(256 + offset)] = value
    added = {token["id"] for token in document.get("added_tokens", [])}
    result = {}
    for spelling, token_id in model["vocab"].items():
        if type(token_id) is not int or token_id < 0 or token_id in result or not spelling:
            raise ValueError("invalid ByteLevel vocabulary")
        if token_id in added:
            continue
        try:
            result[token_id] = bytes(alphabet[character] for character in spelling)
        except KeyError as error:
            raise ValueError("token lies outside the ByteLevel alphabet") from error
    if not result:
        raise ValueError("empty ByteLevel vocabulary")
    return result


class TokenGrammar:
    def __init__(self, rule: EnvelopeGrammar, token_bytes: dict[int, bytes], eos_ids: set[int]):
        if not eos_ids or eos_ids.intersection(token_bytes):
            raise ValueError("EOS must be a separate special-token set")
        self.rule, self.token_bytes, self.eos_ids = rule, token_bytes, eos_ids
        self.output_bytes = b''
        self.ended = False
        self.candidate_checks = 0

    def allows(self, token_id: int) -> bool:
        if self.ended:
            return False
        complete = self.rule.status(self.output_bytes) == "complete"
        if token_id in self.eos_ids:
            return complete
        # Do not let additional whitespace compete with EOS after a complete object.
        if complete:
            return False
        fragment = self.token_bytes.get(token_id)
        return bool(fragment) and self.rule.status(self.output_bytes + fragment) != "invalid"

    def choose(self, ranked_token_ids) -> int:
        for token_id in ranked_token_ids:
            self.candidate_checks += 1
            if self.allows(token_id):
                return token_id
        raise NoAllowedToken("no legal token extends the JSON/UTF-8 prefix")

    def accept(self, token_id: int) -> None:
        if not self.allows(token_id):
            raise ValueError("actual generation departed from the constrained prefix")
        if token_id in self.eos_ids:
            self.ended = True
        else:
            self.output_bytes += self.token_bytes[token_id]


class GrammarLogitsProcessor:
    """Batch-one greedy selection; torch is imported only inside actual calls."""

    def __init__(self, selector: TokenGrammar, input_tokens: int):
        self.selector = selector
        self.input_tokens = input_tokens
        self.accepted_ids = []
        self.mask_seconds = 0.0

    def synchronize(self, generated_ids) -> None:
        actual = list(generated_ids)
        if actual[:len(self.accepted_ids)] != self.accepted_ids or len(actual) < len(self.accepted_ids):
            raise ValueError("generation prefix changed during grammar decoding")
        for token_id in actual[len(self.accepted_ids):]:
            self.selector.accept(token_id)
            self.accepted_ids.append(token_id)

    def __call__(self, input_ids, scores):
        import torch

        started = time.monotonic()
        try:
            if input_ids.shape[0] != 1 or scores.shape[0] != 1:
                raise ValueError("grammar-v1 supports batch-one greedy decoding only")
            self.synchronize(input_ids[0, self.input_tokens:].tolist())
            # One bulk host transfer avoids a GPU synchronization for each candidate.
            # Token selection is host work; the model itself stays on its requested device.
            host_scores = scores[0].detach().cpu()
            if torch.isnan(host_scores).any() or torch.isposinf(host_scores).any():
                raise ValueError("non-finite candidate logits")
            # Stable sorting preserves the lowest token ID for tied greedy scores.
            ranked = torch.argsort(host_scores, descending=True, stable=True).tolist()
            def finite_candidates():
                for token_id in ranked:
                    if not math.isfinite(float(host_scores[token_id])):
                        break
                    yield token_id
            selected = self.selector.choose(finite_candidates())
            constrained = torch.full_like(scores, -float("inf"))
            constrained[0, selected] = scores[0, selected]
            return constrained
        finally:
            self.mask_seconds += time.monotonic() - started

    def evidence(self) -> dict:
        return {"grammarSHA256": self.selector.rule.sha256, "logitSelectionDevice": "cpu",
                "grammarMaskSeconds": self.mask_seconds,
                "grammarCandidateChecks": self.selector.candidate_checks,
                "grammarComplete": self.selector.rule.status(self.selector.output_bytes) == "complete",
                "grammarEOSAccepted": self.selector.ended}
