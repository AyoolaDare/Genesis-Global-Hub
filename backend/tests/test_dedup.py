"""
Genesis Global CMS — Deduplication Logic Tests

Tests the pure deduplication functions without any HTTP layer.
All functions are importable directly from app.services.dedup_service.

Covers:
1.  Phone normalization: +234, 234, 0 prefix variants
2.  Exact name match → 100%
3.  Token-sorted name match (reordered names) → 100%
4.  Fuzzy name match (minor typos) → > 80%
5.  No name match → < 50%
6.  Phone exact match → overall_score >= 85%
7.  Below threshold score → overall_score < 85%
8.  Email exact match scoring
9.  Missing phone or email edge cases
10. Integration: run_dedup_check against in-memory DB
"""
import uuid
from datetime import datetime
from unittest.mock import AsyncMock, patch

import pytest

from app.services.dedup_service import (
    DUPLICATE_THRESHOLD,
    calculate_duplicate_score,
    calculate_email_score,
    calculate_name_similarity,
    normalize_phone,
)


# ── Phone Normalization ────────────────────────────────────────────────────────

class TestNormalizePhone:

    def test_normalize_phone_with_plus_prefix(self):
        assert normalize_phone("+2348012345678") == "08012345678"

    def test_normalize_phone_with_country_code_no_plus(self):
        assert normalize_phone("2348012345678") == "08012345678"

    def test_normalize_phone_already_local(self):
        assert normalize_phone("08012345678") == "08012345678"

    def test_normalize_phone_with_spaces(self):
        result = normalize_phone("0801 234 5678")
        assert result == "08012345678"

    def test_normalize_phone_with_dashes(self):
        result = normalize_phone("080-1234-5678")
        assert result == "08012345678"

    def test_normalize_phone_none_returns_none(self):
        assert normalize_phone(None) is None

    def test_normalize_phone_empty_string_returns_none(self):
        assert normalize_phone("") is None

    def test_normalize_phone_too_short_returns_none(self):
        assert normalize_phone("12345") is None

    def test_normalize_phone_takes_last_11_digits(self):
        # If more than 11 digits after stripping country code
        result = normalize_phone("+2348099887766")
        assert result is not None
        assert len(result) == 11

    def test_normalize_phone_different_formatting_same_result(self):
        """Different representations of same phone must normalize identically."""
        v1 = normalize_phone("08012345678")
        v2 = normalize_phone("+2348012345678")
        v3 = normalize_phone("2348012345678")
        assert v1 == v2 == v3

    def test_normalize_non_digit_only_input_returns_none(self):
        assert normalize_phone("ABCDEF") is None


# ── Name Similarity ────────────────────────────────────────────────────────────

class TestCalculateNameSimilarity:

    def test_exact_name_match_returns_100(self):
        score = calculate_name_similarity("John Doe", "John Doe")
        assert score == 100.0

    def test_exact_name_case_insensitive(self):
        score = calculate_name_similarity("John Doe", "john doe")
        assert score == 100.0

    def test_token_sorted_match_returns_100(self):
        """Names with same tokens in different order should score 100."""
        score = calculate_name_similarity("John Doe", "Doe John")
        assert score == 100.0

    def test_three_part_name_token_reordered(self):
        score = calculate_name_similarity("Adebayo Chukwuemeka Okafor", "Okafor Adebayo Chukwuemeka")
        assert score == 100.0

    def test_fuzzy_name_match_above_80(self):
        """Minor typos should score above 80%."""
        score = calculate_name_similarity("John Doe", "Jon Doe")
        assert score > 80.0

    def test_minor_typo_in_last_name(self):
        score = calculate_name_similarity("Mary Johnson", "Mary Jonson")
        assert score > 75.0

    def test_no_name_match_below_50(self):
        """Completely different names should score below 50%."""
        score = calculate_name_similarity("John Doe", "Mary Johnson")
        assert score < 50.0

    def test_completely_different_names(self):
        score = calculate_name_similarity("Emmanuel Adeyemi", "Ngozi Okafor")
        assert score < 40.0

    def test_empty_name1_returns_zero(self):
        assert calculate_name_similarity("", "John Doe") == 0.0

    def test_empty_name2_returns_zero(self):
        assert calculate_name_similarity("John Doe", "") == 0.0

    def test_both_empty_returns_zero(self):
        assert calculate_name_similarity("", "") == 0.0

    def test_single_matching_token(self):
        """Sharing one token out of two should score somewhere between 0 and 100."""
        score = calculate_name_similarity("John Smith", "John Brown")
        assert 0.0 < score < 100.0

    def test_score_range_is_valid(self):
        """Score must always be in [0.0, 100.0]."""
        score = calculate_name_similarity("Adaeze", "Chinedu Obiechina Nwachukwu")
        assert 0.0 <= score <= 100.0


# ── Email Scoring ──────────────────────────────────────────────────────────────

class TestCalculateEmailScore:

    def test_exact_email_match_returns_100(self):
        assert calculate_email_score("john@test.com", "john@test.com") == 100.0

    def test_case_insensitive_email_match(self):
        assert calculate_email_score("JOHN@TEST.COM", "john@test.com") == 100.0

    def test_different_emails_returns_zero(self):
        assert calculate_email_score("john@test.com", "mary@test.com") == 0.0

    def test_none_email1_returns_zero(self):
        assert calculate_email_score(None, "john@test.com") == 0.0

    def test_none_email2_returns_zero(self):
        assert calculate_email_score("john@test.com", None) == 0.0

    def test_both_none_returns_zero(self):
        assert calculate_email_score(None, None) == 0.0

    def test_email_with_whitespace_normalized(self):
        assert calculate_email_score("  john@test.com  ", "john@test.com") == 100.0


# ── Overall Duplicate Score ────────────────────────────────────────────────────

class TestCalculateDuplicateScore:

    def test_exact_phone_match_score_above_threshold(self):
        """Exact phone match should always produce a score >= DUPLICATE_THRESHOLD."""
        result = calculate_duplicate_score(
            new_name="John Doe",
            new_phone="08012345678",
            new_email="john@test.com",
            existing_name="Different Name",
            existing_phone="08012345678",
            existing_email="other@test.com",
        )
        assert result["overall_score"] >= DUPLICATE_THRESHOLD
        assert result["phone_score"] == 100.0

    def test_exact_phone_same_name_very_high_score(self):
        """Exact phone + exact name should produce near-100 score."""
        result = calculate_duplicate_score(
            new_name="John Doe",
            new_phone="08012345678",
            new_email="john@test.com",
            existing_name="John Doe",
            existing_phone="08012345678",
            existing_email="john@test.com",
        )
        assert result["overall_score"] > 90.0

    def test_different_phone_different_name_below_threshold(self):
        """Completely different data should score below DUPLICATE_THRESHOLD."""
        result = calculate_duplicate_score(
            new_name="John Smith",
            new_phone="08011111111",
            new_email="john@test.com",
            existing_name="Mary Johnson",
            existing_phone="08099999999",
            existing_email="mary@test.com",
        )
        assert result["overall_score"] < DUPLICATE_THRESHOLD

    def test_no_phone_exact_name_email_match(self):
        """Same name and email but no phone — should still score high."""
        result = calculate_duplicate_score(
            new_name="John Doe",
            new_phone=None,
            new_email="john@test.com",
            existing_name="John Doe",
            existing_phone=None,
            existing_email="john@test.com",
        )
        # name_score=100, email_score=100: 0.70*100 + 0.30*100 = 100
        assert result["overall_score"] == 100.0

    def test_phone_match_weight_60_percent(self):
        """
        When phone matches, overall = 0.60 * 100 + 0.40 * name_score.
        With a totally different name (score ~0), overall should be ~60%.
        """
        result = calculate_duplicate_score(
            new_name="John Doe",
            new_phone="08012345678",
            new_email=None,
            existing_name="Zzz Zzz Zzz",  # very different name
            existing_phone="08012345678",
            existing_email=None,
        )
        # phone_score=100 → base of 60, plus 40% of a low name score
        assert result["phone_score"] == 100.0
        assert 60.0 <= result["overall_score"] < 85.0  # name brings it down

    def test_no_phone_email_only_match(self):
        """Email match alone (no phone, different name) scores 0.30 * 100 = 30%."""
        result = calculate_duplicate_score(
            new_name="John Smith",
            new_phone="08011111111",
            new_email="john@test.com",
            existing_name="Mary Johnson",
            existing_phone="08099999999",
            existing_email="john@test.com",
        )
        # name_score ≈ 0-30%, email_score = 100
        # overall ≈ 0.70 * low + 0.30 * 100 = 30-ish%
        assert result["email_score"] == 100.0
        assert result["overall_score"] < DUPLICATE_THRESHOLD

    def test_result_contains_all_expected_keys(self):
        """calculate_duplicate_score must return all expected keys."""
        result = calculate_duplicate_score(
            new_name="Test",
            new_phone="08012345678",
            new_email=None,
            existing_name="Test",
            existing_phone="08012345678",
            existing_email=None,
        )
        assert "overall_score" in result
        assert "phone_score" in result
        assert "name_score" in result
        assert "email_score" in result

    def test_scores_are_rounded_to_two_decimal_places(self):
        """All returned scores must be rounded to 2 decimal places."""
        result = calculate_duplicate_score(
            new_name="Adebayo Emmanuel",
            new_phone="08012300000",
            new_email=None,
            existing_name="Adebayo Emeka",
            existing_phone="08099900000",
            existing_email=None,
        )
        for key in ("overall_score", "phone_score", "name_score", "email_score"):
            val = result[key]
            assert round(val, 2) == val, f"{key}={val} is not rounded to 2 decimal places"

    def test_threshold_constant_is_85(self):
        """The DUPLICATE_THRESHOLD must be exactly 85.0 per spec."""
        assert DUPLICATE_THRESHOLD == 85.0

    def test_phone_normalization_applied_in_scoring(self):
        """Phone comparison should work even with different formatting."""
        result = calculate_duplicate_score(
            new_name="Test User",
            new_phone="+2348012345678",  # international format
            new_email=None,
            existing_name="Test User",
            existing_phone="08012345678",  # local format
            existing_email=None,
        )
        # Should recognize these as the same phone
        assert result["phone_score"] == 100.0
        assert result["overall_score"] >= DUPLICATE_THRESHOLD


# ── Integration: run_dedup_check ──────────────────────────────────────────────

@pytest.mark.asyncio
async def test_run_dedup_check_finds_duplicate(db):
    """run_dedup_check should detect a high-confidence duplicate in the database."""
    from tests.utils import create_active_member
    from app.services.dedup_service import run_dedup_check

    existing = create_active_member(db, full_name="John Adeyemi", phone="08012345678")

    results = await run_dedup_check(
        full_name="John Adeyemi",
        phone="08012345678",
        email=None,
        db=db,
    )

    assert len(results) >= 1
    assert results[0].overall_score >= DUPLICATE_THRESHOLD
    assert results[0].existing_member_id == existing.id


@pytest.mark.asyncio
async def test_run_dedup_check_no_match(db):
    """run_dedup_check should return empty list when no duplicates exist."""
    from tests.utils import create_active_member
    from app.services.dedup_service import run_dedup_check

    create_active_member(db, full_name="Ngozi Okafor", phone="08099999999")

    results = await run_dedup_check(
        full_name="Emmanuel Chukwu",
        phone="08011111111",
        email="different@test.com",
        db=db,
    )

    assert results == []


@pytest.mark.asyncio
async def test_run_dedup_check_excludes_self(db):
    """run_dedup_check should not flag a member against itself (when updating)."""
    from tests.utils import create_active_member
    from app.services.dedup_service import run_dedup_check

    member = create_active_member(db, full_name="Self Exclude Test", phone="08012340000")

    results = await run_dedup_check(
        full_name="Self Exclude Test",
        phone="08012340000",
        email=None,
        db=db,
        exclude_id=member.id,
    )

    matching_self = [r for r in results if r.existing_member_id == member.id]
    assert len(matching_self) == 0


@pytest.mark.asyncio
async def test_run_dedup_check_results_sorted_by_score(db):
    """Results should be sorted descending by overall_score."""
    from tests.utils import create_active_member
    from app.services.dedup_service import run_dedup_check

    # Create two members — one exact phone match, one partial name match
    create_active_member(db, full_name="John Doe", phone="08012345679")
    create_active_member(db, full_name="Jon Doe", phone="08099999998")

    results = await run_dedup_check(
        full_name="John Doe",
        phone="08012345679",
        email=None,
        db=db,
    )

    if len(results) > 1:
        for i in range(len(results) - 1):
            assert results[i].overall_score >= results[i + 1].overall_score
