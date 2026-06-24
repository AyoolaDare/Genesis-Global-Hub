"""
Genesis Global CMS — SendGrid → Brevo compatibility shim

Wraps BrevoClient with the same async method signatures as the original
SendGridClient so existing call-sites (worker tasks, etc.) need no changes.
The sendgrid package is NOT imported here.
"""
import logging

logger = logging.getLogger(__name__)


class SendGridClient:
    """Drop-in SendGridClient powered by BrevoClient under the hood."""

    def __init__(self) -> None:
        try:
            from app.integrations.brevo import BrevoClient
            self._brevo: object | None = BrevoClient()
        except Exception:
            self._brevo = None

    # ------------------------------------------------------------------
    # Internal helper
    # ------------------------------------------------------------------

    def _send(self, to_email: str, subject: str, html_content: str, text_content: str = "") -> bool:
        if not self._brevo:
            return False
        try:
            return self._brevo.send_email(  # type: ignore[union-attr]
                to_email=to_email,
                subject=subject,
                html_content=html_content,
                text_content=text_content,
            )
        except Exception as exc:
            logger.error("SendGridClient(shim) send error: %s", exc)
            return False

    # ------------------------------------------------------------------
    # Public async API (matches the original SendGridClient signatures)
    # ------------------------------------------------------------------

    async def send_password_reset(self, to_email: str, reset_link: str) -> bool:
        subject = "Reset Your Genesis Global Password"
        html = (
            "<html><body>"
            "<h2>Password Reset Request</h2>"
            "<p>We received a request to reset the password for your Genesis Global account.</p>"
            "<p>Click the link below to choose a new password. This link expires in 1 hour.</p>"
            f'<p><a href="{reset_link}" style="display:inline-block;padding:12px 24px;'
            'background:#1a237e;color:#ffffff;text-decoration:none;border-radius:4px;">'
            "Reset Password</a></p>"
            "<p>If you did not request this, please ignore this email.</p>"
            "<hr><p style='color:#666;font-size:12px;'>Genesis Global — Celestial Church of Christ</p>"
            "</body></html>"
        )
        text = f"Reset your Genesis Global password: {reset_link}\nExpires in 1 hour."
        return self._send(to_email, subject, html, text)

    async def send_member_welcome_email(
        self,
        to_email: str,
        member_name: str,
        church_name: str = "Genesis Global",
    ) -> bool:
        subject = f"Welcome to {church_name}!"
        html = (
            f"<html><body><h2>Welcome, {member_name}!</h2>"
            f"<p>We are overjoyed to have you as an official member of <strong>{church_name}</strong>.</p>"
            f"<p>Your membership has been approved and your profile is now active.</p>"
            f"<p>God bless you as you grow with us!</p>"
            f"<p>In Christ's love,<br><strong>The {church_name} Team</strong></p>"
            f"<hr><p style='color:#666;font-size:12px;'>{church_name} — Celestial Church of Christ</p>"
            f"</body></html>"
        )
        text = f"Welcome to {church_name}, {member_name}!\nYour membership has been approved."
        return self._send(to_email, subject, html, text)

    async def send_pending_approval_notification(
        self,
        admin_email: str,
        member_name: str,
        submitted_by: str,
        approval_link: str,
    ) -> bool:
        subject = f"Action Required: Member Approval — {member_name}"
        html = (
            "<html><body><h2>New Member Pending Approval</h2>"
            "<p>A new member record requires your review and approval.</p>"
            f"<p><strong>Member:</strong> {member_name}<br>"
            f"<strong>Submitted By:</strong> {submitted_by}</p>"
            f'<p><a href="{approval_link}" style="display:inline-block;padding:12px 24px;'
            'background:#1b5e20;color:#ffffff;text-decoration:none;border-radius:4px;">'
            "Review &amp; Approve</a></p>"
            "<hr><p style='color:#666;font-size:12px;'>Genesis Global CMS — Automated Notification</p>"
            "</body></html>"
        )
        text = f"New member pending approval:\n  Name: {member_name}\n  Submitted by: {submitted_by}\nReview: {approval_link}"
        return self._send(admin_email, subject, html, text)

    async def send_annual_sponsor_report(
        self,
        to_email: str,
        sponsor_name: str,
        total_given: float,
        payment_count: int,
        year: int,
    ) -> bool:
        subject = f"Your Genesis Global Giving Report — {year}"
        formatted = f"₦{total_given:,.2f}"
        html = (
            f"<html><body><h2>Your {year} Giving Report</h2>"
            f"<p>Dear {sponsor_name},</p>"
            f"<p>Thank you for your generous and faithful support throughout {year}.</p>"
            f"<table cellpadding='10' border='1' style='border-collapse:collapse;'>"
            f"<tr style='background:#1a237e;color:#fff;'><th>Year</th><th>Total Given</th><th>Payments</th></tr>"
            f"<tr><td>{year}</td><td>{formatted}</td><td>{payment_count}</td></tr>"
            f"</table>"
            f"<p>May God multiply back to you abundantly!</p>"
            f"<p><strong>The Genesis Global Finance Team</strong></p>"
            f"<hr><p style='color:#666;font-size:12px;'>Automated annual report.</p>"
            f"</body></html>"
        )
        text = f"Dear {sponsor_name},\nYour {year} giving report:\n  Total: {formatted}\n  Payments: {payment_count}\nThank you!"
        return self._send(to_email, subject, html, text)

    async def send_follow_up_escalation(
        self,
        supervisor_email: str,
        worker_name: str,
        contact_name: str,
        hours_overdue: int,
    ) -> bool:
        subject = f"Escalation: Overdue Follow-Up — {contact_name}"
        html = (
            "<html><body>"
            "<h2 style='color:#b71c1c;'>Follow-Up Task Escalated</h2>"
            "<p>A follow-up task has been automatically escalated because it is overdue.</p>"
            f"<p><strong>Contact:</strong> {contact_name}<br>"
            f"<strong>Assigned Worker:</strong> {worker_name}<br>"
            f"<strong>Hours Overdue:</strong> <span style='color:#b71c1c;'>{hours_overdue}</span></p>"
            "<p>Please log in to the Genesis Global CMS and action this immediately.</p>"
            "<hr><p style='color:#666;font-size:12px;'>Genesis Global CMS — Automated Escalation Alert</p>"
            "</body></html>"
        )
        text = f"ESCALATION: Overdue Follow-Up\nContact: {contact_name}\nWorker: {worker_name}\nHours Overdue: {hours_overdue}"
        return self._send(supervisor_email, subject, html, text)


# Singleton used throughout the application
sendgrid_client = SendGridClient()
