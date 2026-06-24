"""
Genesis Global CMS — Termii SMS / WhatsApp Integration

Handles:
  - Sending single and bulk SMS messages
  - Sending WhatsApp messages via Termii
  - Nigerian phone number normalization
  - Template-based messaging
"""
import logging
import re

import httpx

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

# ── SMS / WhatsApp Templates ───────────────────────────────────────────────────

TEMPLATES: dict[str, str] = {
    "welcome_member": (
        "Welcome to Genesis Global! {name}, we're glad you're part of our family. "
        "God bless you!"
    ),
    "payment_thank_you": (
        "Thank you {name} for your generous support of N{amount}. "
        "God bless you! - Genesis Global"
    ),
    "payment_reminder": (
        "Dear {name}, your Genesis Global sponsorship of N{amount} is due on {date}. "
        "God bless you!"
    ),
    "payment_overdue": (
        "Dear {name}, your Genesis Global sponsorship of N{amount} was due on {date}. "
        "Please reach out if you need assistance. God bless!"
    ),
    "follow_up_assigned": (
        "Hello {name}, you have been assigned a new follow-up contact: {contact_name}. "
        "Please reach out within 48 hours."
    ),
    "new_convert_welcome": (
        "Welcome {name}! We're so glad you visited Genesis Global. "
        "Someone from our team will reach out to you soon. God bless!"
    ),
    "follow_up_reminder": (
        "Hi {name}, you have {count} pending follow-up(s) due today. "
        "Log in to view them."
    ),
    "follow_up_escalation": (
        "Hi {name}, follow-up task for {contact_name} is overdue by {hours} hours "
        "and has been escalated to you. Please action immediately."
    ),
    "inactive_member_alert": (
        "Hi {name}, member {member_name} has not attended any meeting in the last 30 days "
        "and has been flagged as At Risk. Please follow up."
    ),
    "payment_overdue_coordinator": (
        "Finance Alert: Sponsor {sponsor_name} is {days} days overdue on their "
        "N{amount} {tier} sponsorship. Please follow up."
    ),
}


class TermiiClient:
    """Async HTTP client for the Termii API."""

    BASE_URL = "https://api.ng.termii.com/api"

    def normalize_phone(self, phone: str) -> str:
        """
        Convert a Nigerian phone number to international E.164 format (without +).

        Transformations:
          0XXXXXXXXXX    → 234XXXXXXXXXX
          +234XXXXXXXXXX → 234XXXXXXXXXX
          234XXXXXXXXXX  → 234XXXXXXXXXX (no change)

        Args:
            phone: Raw phone number string.

        Returns:
            Normalized phone string with country code but no '+'.

        Raises:
            ValueError: If the phone number cannot be normalized to a valid format.
        """
        # Strip all non-digit characters except leading +
        cleaned = re.sub(r"[^\d+]", "", phone.strip())

        if cleaned.startswith("+234"):
            normalized = cleaned[1:]  # remove '+'
        elif cleaned.startswith("234"):
            normalized = cleaned
        elif cleaned.startswith("0") and len(cleaned) == 11:
            normalized = "234" + cleaned[1:]
        elif len(cleaned) == 10 and not cleaned.startswith("0"):
            # Bare 10-digit number without leading 0
            normalized = "234" + cleaned
        else:
            # Return as-is; let Termii surface the error
            logger.warning("Could not normalize phone number '%s' — passing as-is", phone)
            return cleaned

        if not re.match(r"^234\d{10}$", normalized):
            logger.warning(
                "Normalized phone '%s' may not be valid Nigerian format (from '%s')",
                normalized,
                phone,
            )
        return normalized

    async def _post(self, endpoint: str, payload: dict) -> dict:
        """Internal helper that POSTs JSON to a Termii endpoint and returns parsed JSON."""
        async with httpx.AsyncClient(timeout=30.0) as http:
            response = await http.post(f"{self.BASE_URL}{endpoint}", json=payload)
            response.raise_for_status()
            return response.json()

    async def send_sms(
        self,
        to: str,
        message: str,
        channel: str = "generic",
    ) -> dict:
        """
        Send a single SMS message via Termii.

        POST /sms/send

        Args:
            to:      Recipient phone number (will be normalized to international format).
            message: SMS message body text.
            channel: Termii channel — 'generic', 'dnd', or 'whatsapp'.

        Returns:
            Parsed JSON response from Termii including message_id, balance, etc.

        Raises:
            httpx.HTTPStatusError: On non-2xx responses.
            httpx.RequestError:    On network failures.
        """
        normalized_to = self.normalize_phone(to)
        payload = {
            "to": normalized_to,
            "from": settings.TERMII_SENDER_ID,
            "sms": message,
            "type": "plain",
            "channel": channel,
            "api_key": settings.TERMII_API_KEY,
        }
        try:
            data = await self._post("/sms/send", payload)
            logger.info(
                "Termii SMS sent: to=%s channel=%s message_id=%s",
                normalized_to,
                channel,
                data.get("message_id"),
            )
            return data
        except httpx.HTTPStatusError as exc:
            logger.error(
                "Termii send_sms HTTP error: to=%s status=%s body=%s",
                normalized_to,
                exc.response.status_code,
                exc.response.text,
            )
            raise
        except httpx.RequestError as exc:
            logger.error(
                "Termii send_sms network error: to=%s error=%s",
                normalized_to,
                str(exc),
            )
            raise

    async def send_bulk_sms(self, recipients: list[dict], message: str) -> dict:
        """
        Send a bulk SMS to multiple recipients via Termii.

        POST /sms/send/bulk

        Args:
            recipients: List of dicts, each containing at minimum {"phone_number": "..."}.
                        Phone numbers are normalized automatically.
            message:    SMS body text sent to all recipients.

        Returns:
            Parsed JSON response from Termii.
        """
        normalized_recipients = []
        for r in recipients:
            phone = r.get("phone_number", r.get("phone", ""))
            if phone:
                normalized_recipients.append({
                    **r,
                    "phone_number": self.normalize_phone(phone),
                })

        to_list = [r["phone_number"] for r in normalized_recipients if r.get("phone_number")]

        payload = {
            "to": to_list,
            "from": settings.TERMII_SENDER_ID,
            "sms": message,
            "type": "plain",
            "channel": "generic",
            "api_key": settings.TERMII_API_KEY,
        }
        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                response = await client.post(
                    f"{self.BASE_URL}/sms/send/bulk",
                    json=payload,
                )
                response.raise_for_status()
                data = response.json()
                logger.info(
                    "Termii bulk SMS sent: count=%s",
                    len(to_list),
                )
                return data
        except httpx.HTTPStatusError as exc:
            logger.error(
                "Termii send_bulk_sms HTTP error: status=%s body=%s",
                exc.response.status_code,
                exc.response.text,
            )
            raise
        except httpx.RequestError as exc:
            logger.error("Termii send_bulk_sms network error: %s", str(exc))
            raise

    async def send_whatsapp(self, to: str, message: str) -> dict:
        """
        Send a WhatsApp message via Termii.

        Delegates to send_sms with channel='whatsapp'.

        Args:
            to:      Recipient phone number.
            message: Message text.

        Returns:
            Parsed JSON response from Termii.
        """
        return await self.send_sms(to=to, message=message, channel="whatsapp")

    async def send_templated_message(
        self,
        to: str,
        template_key: str,
        template_vars: dict,
        channel: str = "generic",
    ) -> dict:
        """
        Look up a named template, format it with the provided variables, and send it.

        Args:
            to:             Recipient phone number.
            template_key:   Key from the TEMPLATES dict (e.g. "welcome_member").
            template_vars:  Dict of substitution variables for the template.
            channel:        Termii channel ('generic', 'dnd', 'whatsapp').

        Returns:
            Parsed JSON response from Termii.

        Raises:
            KeyError: If template_key is not found in TEMPLATES.
        """
        if template_key not in TEMPLATES:
            raise KeyError(
                f"Unknown SMS template '{template_key}'. "
                f"Available: {list(TEMPLATES.keys())}"
            )
        template = TEMPLATES[template_key]
        try:
            message = template.format(**template_vars)
        except KeyError as exc:
            logger.error(
                "Template '%s' missing variable: %s (provided: %s)",
                template_key,
                exc,
                list(template_vars.keys()),
            )
            raise

        return await self.send_sms(to=to, message=message, channel=channel)


# Singleton instance used throughout the application
termii = TermiiClient()
