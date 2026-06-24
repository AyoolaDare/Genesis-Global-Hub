"""
Genesis Global CMS — Brevo (formerly Sendinblue) Email Integration

Sends transactional emails via the Brevo REST API using httpx.
No SDK dependency — uses the raw API with the api-key header.
"""
import logging

import httpx

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

BREVO_API_URL = "https://api.brevo.com/v3/smtp/email"


class BrevoClient:
    """Thin wrapper around Brevo's transactional email REST API."""

    def _headers(self) -> dict:
        return {
            "accept": "application/json",
            "api-key": settings.BREVO_API_KEY,
            "content-type": "application/json",
        }

    def send_email(
        self,
        to_email: str,
        subject: str,
        html_content: str,
        text_content: str = "",
        to_name: str = "",
    ) -> bool:
        """
        Send a transactional email via Brevo.

        Returns True if accepted (2xx), False on any error.
        """
        if not settings.BREVO_API_KEY:
            logger.warning("BREVO_API_KEY not configured — email not sent to %s", to_email)
            return False

        payload: dict = {
            "sender": {
                "name": "Genesis Global",
                "email": settings.FROM_EMAIL,
            },
            "to": [{"email": to_email, "name": to_name or to_email}],
            "subject": subject,
            "htmlContent": html_content,
        }
        if text_content:
            payload["textContent"] = text_content

        try:
            response = httpx.post(
                BREVO_API_URL,
                json=payload,
                headers=self._headers(),
                timeout=15.0,
            )
            if 200 <= response.status_code < 300:
                logger.info("Brevo email sent: to=%s subject=%s", to_email, subject)
                return True
            logger.warning(
                "Brevo email non-2xx: to=%s status=%s body=%s",
                to_email,
                response.status_code,
                response.text,
            )
            return False
        except Exception as exc:
            logger.error("Brevo send error: %s", str(exc), exc_info=True)
            return False

    def send_password_reset(self, to_email: str, reset_link: str) -> bool:
        html = f"""
        <html><body>
        <h2>Password Reset Request</h2>
        <p>We received a request to reset the password for your Genesis Global account.</p>
        <p>Click the link below to choose a new password. This link expires in 1 hour.</p>
        <p><a href="{reset_link}" style="display:inline-block;padding:12px 24px;
            background:#1a237e;color:#ffffff;text-decoration:none;border-radius:4px;">
            Reset Password</a></p>
        <p>If you did not request this, please ignore this email.</p>
        <hr><p style="color:#666;font-size:12px;">Genesis Global — Celestial Church of Christ</p>
        </body></html>"""
        text = (
            f"Reset your Genesis Global password by visiting: {reset_link}\n\n"
            "This link expires in 1 hour. If you didn't request this, ignore this email."
        )
        return self.send_email(
            to_email=to_email,
            subject="Reset Your Genesis Global Password",
            html_content=html,
            text_content=text,
        )

    def send_member_welcome_email(
        self, to_email: str, member_name: str, church_name: str = "Genesis Global"
    ) -> bool:
        html = f"""
        <html><body>
        <h2>Welcome, {member_name}!</h2>
        <p>We are overjoyed to have you as an official member of <strong>{church_name}</strong>.</p>
        <p>Your membership has been approved and your profile is now active.</p>
        <p>God bless you as you grow with us!</p>
        <p>In Christ's love,<br><strong>The {church_name} Team</strong></p>
        <hr><p style="color:#666;font-size:12px;">{church_name} — Celestial Church of Christ</p>
        </body></html>"""
        text = (
            f"Welcome to {church_name}, {member_name}!\n\n"
            "Your membership has been approved. God bless you!\n"
            f"The {church_name} Team"
        )
        return self.send_email(
            to_email=to_email,
            subject=f"Welcome to {church_name}!",
            html_content=html,
            text_content=text,
            to_name=member_name,
        )

    def send_pending_approval_notification(
        self,
        admin_email: str,
        member_name: str,
        submitted_by: str,
        approval_link: str,
    ) -> bool:
        html = f"""
        <html><body>
        <h2>New Member Pending Approval</h2>
        <p>A new member record requires your review and approval.</p>
        <table cellpadding="8"><tr><td><b>Member Name:</b></td><td>{member_name}</td></tr>
        <tr><td><b>Submitted By:</b></td><td>{submitted_by}</td></tr></table><br>
        <p><a href="{approval_link}" style="display:inline-block;padding:12px 24px;
            background:#1b5e20;color:#ffffff;text-decoration:none;border-radius:4px;">
            Review &amp; Approve</a></p>
        <hr><p style="color:#666;font-size:12px;">Genesis Global CMS — Automated Notification</p>
        </body></html>"""
        text = (
            f"New member pending approval:\n  Name: {member_name}\n"
            f"  Submitted by: {submitted_by}\n\nReview here: {approval_link}"
        )
        return self.send_email(
            to_email=admin_email,
            subject=f"Action Required: Member Approval — {member_name}",
            html_content=html,
            text_content=text,
        )

    def send_annual_sponsor_report(
        self,
        to_email: str,
        sponsor_name: str,
        total_given: float,
        payment_count: int,
        year: int,
    ) -> bool:
        amount = f"₦{total_given:,.2f}"
        html = f"""
        <html><body>
        <h2>Your {year} Giving Report</h2>
        <p>Dear {sponsor_name}, thank you for your generous support of Genesis Global in {year}.</p>
        <table border="1" cellpadding="10" style="border-collapse:collapse;">
        <tr style="background:#1a237e;color:#fff;"><th>Year</th><th>Total Given</th><th>Payments</th></tr>
        <tr><td>{year}</td><td>{amount}</td><td>{payment_count}</td></tr>
        </table>
        <p>May God multiply back to you abundantly!</p>
        <p>The Genesis Global Finance Team</p>
        <hr><p style="color:#666;font-size:12px;">Automated annual report.</p>
        </body></html>"""
        text = (
            f"Dear {sponsor_name},\n\nYour {year} Genesis Global Giving Report:\n"
            f"  Total Given: {amount}\n  Payments Made: {payment_count}\n\n"
            "Thank you for your faithful support. God bless you!\nThe Genesis Global Finance Team"
        )
        return self.send_email(
            to_email=to_email,
            subject=f"Your Genesis Global Giving Report — {year}",
            html_content=html,
            text_content=text,
            to_name=sponsor_name,
        )

    def send_follow_up_escalation(
        self,
        supervisor_email: str,
        worker_name: str,
        contact_name: str,
        hours_overdue: int,
    ) -> bool:
        html = f"""
        <html><body>
        <h2 style="color:#b71c1c;">Follow-Up Task Escalated</h2>
        <p>A follow-up task is overdue and has been escalated to you.</p>
        <table cellpadding="8">
        <tr><td><b>Contact:</b></td><td>{contact_name}</td></tr>
        <tr><td><b>Assigned Worker:</b></td><td>{worker_name}</td></tr>
        <tr><td><b>Hours Overdue:</b></td><td style="color:#b71c1c;">{hours_overdue} hours</td></tr>
        </table>
        <p>Please log in to Genesis Global CMS and action this immediately.</p>
        <hr><p style="color:#666;font-size:12px;">Genesis Global CMS — Automated Escalation Alert</p>
        </body></html>"""
        text = (
            f"ESCALATION: Overdue Follow-Up\n\nContact: {contact_name}\n"
            f"Assigned To: {worker_name}\nHours Overdue: {hours_overdue}\n\n"
            "Please log in and action this immediately."
        )
        return self.send_email(
            to_email=supervisor_email,
            subject=f"Escalation: Overdue Follow-Up — {contact_name}",
            html_content=html,
            text_content=text,
        )


brevo_client = BrevoClient()
