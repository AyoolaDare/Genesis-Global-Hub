"""
Genesis Global CMS — Flutterwave Payment Integration

Handles:
  - Initiating payment links via Flutterwave Standard
  - Verifying transactions by ID or tx_ref
  - HMAC-SHA256 webhook signature verification
  - Calculating next payment due dates per sponsorship tier
"""
import hashlib
import hmac
import logging
import uuid
from datetime import date
from typing import Optional

import httpx

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()


class FlutterwaveClient:
    """Async HTTP client for the Flutterwave v3 API."""

    BASE_URL = "https://api.flutterwave.com/v3"

    def _headers(self) -> dict:
        return {
            "Authorization": f"Bearer {settings.FLUTTERWAVE_SECRET_KEY}",
            "Content-Type": "application/json",
        }

    async def initiate_payment(
        self,
        tx_ref: str,
        amount: float,
        redirect_url: str,
        customer_email: str,
        customer_name: str,
        customer_phone: str,
        currency: str = "NGN",
        payment_title: str = "Genesis Global Sponsorship",
        meta: Optional[dict] = None,
    ) -> dict:
        """
        Create a Flutterwave Standard payment link.

        POST /payments
        Returns: {"status": "success", "message": "...", "data": {"link": "https://..."}}

        Args:
            tx_ref:         Unique transaction reference (e.g. "genesis-{sponsor_id}-{uuid}").
            amount:         Amount to charge.
            redirect_url:   URL to redirect user after payment completion.
            customer_email: Customer's email address.
            customer_name:  Customer's full name.
            customer_phone: Customer's phone number.
            currency:       ISO currency code (default: "NGN").
            payment_title:  Title displayed on payment page.
            meta:           Optional extra metadata dict attached to the transaction.

        Returns:
            Parsed JSON response dict from Flutterwave.

        Raises:
            httpx.HTTPStatusError: On non-2xx responses.
            httpx.RequestError:    On network failures.
        """
        payload: dict = {
            "tx_ref": tx_ref,
            "amount": amount,
            "currency": currency,
            "redirect_url": redirect_url,
            "payment_options": "card,banktransfer,ussd",
            "customer": {
                "email": customer_email,
                "phone_number": customer_phone,
                "name": customer_name,
            },
            "customizations": {
                "title": payment_title,
                "description": "Genesis Global Church — Sponsorship",
                "logo": "",
            },
        }
        if meta:
            payload["meta"] = meta

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    f"{self.BASE_URL}/payments",
                    json=payload,
                    headers=self._headers(),
                )
                response.raise_for_status()
                data = response.json()
                logger.info(
                    "Flutterwave payment initiated: tx_ref=%s status=%s",
                    tx_ref,
                    data.get("status"),
                )
                return data
        except httpx.HTTPStatusError as exc:
            logger.error(
                "Flutterwave initiate_payment HTTP error: tx_ref=%s status=%s body=%s",
                tx_ref,
                exc.response.status_code,
                exc.response.text,
            )
            raise
        except httpx.RequestError as exc:
            logger.error(
                "Flutterwave initiate_payment network error: tx_ref=%s error=%s",
                tx_ref,
                str(exc),
            )
            raise

    async def verify_payment(self, tx_id: str) -> dict:
        """
        Verify a payment by Flutterwave transaction ID.

        GET /transactions/{tx_id}/verify
        Returns transaction details including status, amount, currency, customer.

        Args:
            tx_id: Flutterwave's numeric transaction ID (from webhook data.id).

        Returns:
            Parsed JSON response dict.
        """
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.get(
                    f"{self.BASE_URL}/transactions/{tx_id}/verify",
                    headers=self._headers(),
                )
                response.raise_for_status()
                data = response.json()
                logger.info(
                    "Flutterwave payment verified: tx_id=%s status=%s",
                    tx_id,
                    data.get("data", {}).get("status"),
                )
                return data
        except httpx.HTTPStatusError as exc:
            logger.error(
                "Flutterwave verify_payment HTTP error: tx_id=%s status=%s body=%s",
                tx_id,
                exc.response.status_code,
                exc.response.text,
            )
            raise
        except httpx.RequestError as exc:
            logger.error(
                "Flutterwave verify_payment network error: tx_id=%s error=%s",
                tx_id,
                str(exc),
            )
            raise

    async def get_transaction_by_ref(self, tx_ref: str) -> dict:
        """
        Query Flutterwave for a transaction by our internal tx_ref.

        GET /transactions?tx_ref={tx_ref}
        Returns the matching transaction record(s).

        Args:
            tx_ref: Our unique transaction reference string.

        Returns:
            Parsed JSON response dict.
        """
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.get(
                    f"{self.BASE_URL}/transactions",
                    params={"tx_ref": tx_ref},
                    headers=self._headers(),
                )
                response.raise_for_status()
                data = response.json()
                logger.info(
                    "Flutterwave get_transaction_by_ref: tx_ref=%s count=%s",
                    tx_ref,
                    len(data.get("data", [])),
                )
                return data
        except httpx.HTTPStatusError as exc:
            logger.error(
                "Flutterwave get_transaction_by_ref HTTP error: tx_ref=%s status=%s body=%s",
                tx_ref,
                exc.response.status_code,
                exc.response.text,
            )
            raise
        except httpx.RequestError as exc:
            logger.error(
                "Flutterwave get_transaction_by_ref network error: tx_ref=%s error=%s",
                tx_ref,
                str(exc),
            )
            raise

    def verify_webhook_signature(self, payload: bytes, signature: str) -> bool:
        """
        Verify an incoming Flutterwave webhook's HMAC-SHA256 signature.

        Flutterwave signs the raw request body with your secret key and sends
        the hex digest in the "verif-hash" header.

        Args:
            payload:   Raw request body bytes.
            signature: Value from the "verif-hash" request header.

        Returns:
            True if the signature is valid, False otherwise.
        """
        if not signature:
            logger.warning("Flutterwave webhook received with no verif-hash header")
            return False
        try:
            expected = hmac.new(
                settings.FLUTTERWAVE_SECRET_KEY.encode("utf-8"),
                payload,
                hashlib.sha256,
            ).hexdigest()
            return hmac.compare_digest(expected, signature)
        except Exception as exc:
            logger.error("Flutterwave signature verification error: %s", str(exc))
            return False

    def build_tx_ref(self, sponsor_id: str) -> str:
        """
        Build a unique transaction reference in the format:
        genesis-{sponsor_id}-{short_uuid}

        Args:
            sponsor_id: UUID string of the sponsor.

        Returns:
            Unique tx_ref string safe for Flutterwave.
        """
        short = str(uuid.uuid4()).replace("-", "")[:12]
        return f"genesis-{sponsor_id}-{short}"

    def calculate_next_due_date(self, tier: str, from_date: date) -> Optional[date]:
        """
        Calculate the next payment due date based on sponsorship tier.

        Args:
            tier:      One of MONTHLY, QUARTERLY, ANNUAL, ONE_TIME.
            from_date: The reference date (usually today or last payment date).

        Returns:
            Next due date, or None for ONE_TIME sponsors.
        """
        from dateutil.relativedelta import relativedelta

        tier_upper = tier.upper() if tier else ""

        if tier_upper == "MONTHLY":
            return from_date + relativedelta(months=1)
        elif tier_upper == "QUARTERLY":
            return from_date + relativedelta(months=3)
        elif tier_upper == "ANNUAL":
            return from_date + relativedelta(years=1)
        elif tier_upper == "ONE_TIME":
            return None
        else:
            logger.warning("Unknown sponsorship tier '%s' — returning None for next_due_date", tier)
            return None


# Singleton instance used throughout the application
flutterwave = FlutterwaveClient()
