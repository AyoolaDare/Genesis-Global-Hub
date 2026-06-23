"""
Genesis Global CMS — SendGrid Email Integration

Handles transactional emails:
  - Password reset
  - Member welcome
  - Pending approval notification to admin
  - Annual sponsor reports
  - Follow-up escalation alerts
"""
import logging
from typing import Optional

from sendgrid import SendGridAPIClient
from sendgrid.helpers.mail import Mail, To, Content

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()


class SendGridClient:
    """Wrapper around the SendGrid Python SDK for Genesis Global transactional email."""

    def _send(self, message: Mail) -> bool:
        """
        Internal helper: submit a SendGrid Mail object and handle errors.

        Args:
            message: Constructed Mail object ready to send.

        Returns:
            True if accepted (2xx), False on any error.
        """
        try:
            sg = SendGridAPIClient(settings.SENDGRID_API_KEY)
            response = sg.send(message)
            accepted = 200 <= response.status_code < 300
            if accepted:
                logger.info(
                    "SendGrid email sent: to=%s subject=%s status=%s",
                    message.to,
                    message.subject,
                    response.status_code,
                )
            else:
                logger.warning(
                    "SendGrid email non-2xx: to=%s status=%s body=%s",
                    message.to,
                    response.status_code,
                    response.body,
                )
            return accepted
        except Exception as exc:
            logger.error("SendGrid send error: %s", str(exc), exc_info=True)
            return False

    async def send_password_reset(self, to_email: str, reset_link: str) -> bool:
        """
        Send a password reset email with a secure reset link.

        Args:
            to_email:   Recipient email address.
            reset_link: Full URL the user clicks to reset their password.

        Returns:
            True if email was accepted by SendGrid, False on failure.
        """
        subject = "Reset Your Genesis Global Password"
        html_content = f"""
        <html><body>
        <h2>Password Reset Request</h2>
        <p>We received a request to reset the password for your Genesis Global account.</p>
        <p>Click the link below to choose a new password. This link expires in 1 hour.</p>
        <p><a href="{reset_link}" style="
            display:inline-block;
            padding:12px 24px;
            background:#1a237e;
            color:#ffffff;
            text-decoration:none;
            border-radius:4px;
        ">Reset Password</a></p>
        <p>If you did not request this, please ignore this email. Your password will remain unchanged.</p>
        <hr>
        <p style="color:#666;font-size:12px;">Genesis Global — Celestial Church of Christ</p>
        </body></html>
        """
        plain_content = (
            f"Reset your Genesis Global password by visiting: {reset_link}\n\n"
            f"This link expires in 1 hour. If you didn't request this, ignore this email."
        )
        message = Mail(
            from_email=settings.FROM_EMAIL,
            to_emails=to_email,
            subject=subject,
            html_content=html_content,
        )
        message.plain_text_content = plain_content
        return self._send(message)

    async def send_member_welcome_email(
        self,
        to_email: str,
        member_name: str,
        church_name: str = "Genesis Global",
    ) -> bool:
        """
        Send a warm welcome email to a newly approved member.

        Args:
            to_email:    Member's email address.
            member_name: Member's full name.
            church_name: Church name for the email greeting (default: Genesis Global).

        Returns:
            True if accepted by SendGrid, False on failure.
        """
        subject = f"Welcome to {church_name}!"
        html_content = f"""
        <html><body>
        <h2>Welcome, {member_name}!</h2>
        <p>We are overjoyed to have you as an official member of <strong>{church_name}</strong>.</p>
        <p>
          You are now part of a loving family committed to faith, service, and community.
          Your membership has been approved and your profile is now active.
        </p>
        <p>Here are a few things you can do next:</p>
        <ul>
          <li>Attend our weekly services and department meetings</li>
          <li>Connect with a small group or department</li>
          <li>Download our church app for updates and announcements</li>
        </ul>
        <p>God bless you as you grow with us!</p>
        <p>In Christ's love,<br><strong>The {church_name} Team</strong></p>
        <hr>
        <p style="color:#666;font-size:12px;">{church_name} — Celestial Church of Christ</p>
        </body></html>
        """
        plain_content = (
            f"Welcome to {church_name}, {member_name}!\n\n"
            f"Your membership has been approved. We are glad to have you with us.\n\n"
            f"God bless you!\nThe {church_name} Team"
        )
        message = Mail(
            from_email=settings.FROM_EMAIL,
            to_emails=to_email,
            subject=subject,
            html_content=html_content,
        )
        message.plain_text_content = plain_content
        return self._send(message)

    async def send_pending_approval_notification(
        self,
        admin_email: str,
        member_name: str,
        submitted_by: str,
        approval_link: str,
    ) -> bool:
        """
        Notify an admin that a new member record is pending their approval.

        Args:
            admin_email:   Admin's email address.
            member_name:   Name of the member awaiting approval.
            submitted_by:  Name or email of the staff who submitted the record.
            approval_link: Direct URL to the approval page in the admin portal.

        Returns:
            True if accepted by SendGrid, False on failure.
        """
        subject = f"Action Required: Member Approval — {member_name}"
        html_content = f"""
        <html><body>
        <h2>New Member Pending Approval</h2>
        <p>A new member record requires your review and approval.</p>
        <table cellpadding="8" cellspacing="0">
          <tr><td><strong>Member Name:</strong></td><td>{member_name}</td></tr>
          <tr><td><strong>Submitted By:</strong></td><td>{submitted_by}</td></tr>
        </table>
        <br>
        <p>
          <a href="{approval_link}" style="
            display:inline-block;
            padding:12px 24px;
            background:#1b5e20;
            color:#ffffff;
            text-decoration:none;
            border-radius:4px;
          ">Review & Approve</a>
        </p>
        <p>Please action this within 48 hours. If you have any questions, log in to the admin portal.</p>
        <hr>
        <p style="color:#666;font-size:12px;">Genesis Global CMS — Automated Notification</p>
        </body></html>
        """
        plain_content = (
            f"New member pending approval:\n"
            f"  Name: {member_name}\n"
            f"  Submitted by: {submitted_by}\n\n"
            f"Review here: {approval_link}"
        )
        message = Mail(
            from_email=settings.FROM_EMAIL,
            to_emails=admin_email,
            subject=subject,
            html_content=html_content,
        )
        message.plain_text_content = plain_content
        return self._send(message)

    async def send_annual_sponsor_report(
        self,
        to_email: str,
        sponsor_name: str,
        total_given: float,
        payment_count: int,
        year: int,
    ) -> bool:
        """
        Send a personalised annual giving report to a sponsor.

        Args:
            to_email:      Sponsor's email address.
            sponsor_name:  Sponsor's full name.
            total_given:   Total amount (NGN) donated during the year.
            payment_count: Number of individual payments made.
            year:          The calendar year being reported on.

        Returns:
            True if accepted by SendGrid, False on failure.
        """
        subject = f"Your Genesis Global Giving Report — {year}"
        formatted_amount = f"₦{total_given:,.2f}"
        html_content = f"""
        <html><body>
        <h2>Your {year} Giving Report</h2>
        <p>Dear {sponsor_name},</p>
        <p>
          Thank you for your generous and faithful support of Genesis Global throughout {year}.
          Here is a summary of your giving:
        </p>
        <table cellpadding="10" cellspacing="0" border="1" style="border-collapse:collapse;">
          <tr style="background:#1a237e;color:#ffffff;">
            <th>Year</th><th>Total Given</th><th>Payments Made</th>
          </tr>
          <tr>
            <td style="text-align:center;">{year}</td>
            <td style="text-align:center;">{formatted_amount}</td>
            <td style="text-align:center;">{payment_count}</td>
          </tr>
        </table>
        <br>
        <p>
          Your generosity makes a real difference — funding outreach, welfare, and ministry.
          We are deeply grateful. May God multiply back to you abundantly!
        </p>
        <p>With gratitude,<br><strong>The Genesis Global Finance Team</strong></p>
        <hr>
        <p style="color:#666;font-size:12px;">
          This is an automated annual report. For queries, contact our finance office.
        </p>
        </body></html>
        """
        plain_content = (
            f"Dear {sponsor_name},\n\n"
            f"Your {year} Genesis Global Giving Report:\n"
            f"  Total Given: {formatted_amount}\n"
            f"  Payments Made: {payment_count}\n\n"
            f"Thank you for your faithful support. God bless you!\n\n"
            f"The Genesis Global Finance Team"
        )
        message = Mail(
            from_email=settings.FROM_EMAIL,
            to_emails=to_email,
            subject=subject,
            html_content=html_content,
        )
        message.plain_text_content = plain_content
        return self._send(message)

    async def send_follow_up_escalation(
        self,
        supervisor_email: str,
        worker_name: str,
        contact_name: str,
        hours_overdue: int,
    ) -> bool:
        """
        Notify a supervisor that a follow-up task is overdue and has been escalated.

        Args:
            supervisor_email: Supervisor's email address.
            worker_name:      Name of the worker who was originally assigned the task.
            contact_name:     Name of the follow-up contact who was not contacted.
            hours_overdue:    How many hours past the deadline the task is.

        Returns:
            True if accepted by SendGrid, False on failure.
        """
        subject = f"Escalation: Overdue Follow-Up — {contact_name}"
        html_content = f"""
        <html><body>
        <h2 style="color:#b71c1c;">Follow-Up Task Escalated</h2>
        <p>A follow-up task has been automatically escalated to you because it is overdue.</p>
        <table cellpadding="8" cellspacing="0">
          <tr><td><strong>Contact:</strong></td><td>{contact_name}</td></tr>
          <tr><td><strong>Assigned Worker:</strong></td><td>{worker_name}</td></tr>
          <tr>
            <td><strong>Hours Overdue:</strong></td>
            <td style="color:#b71c1c;">{hours_overdue} hours</td>
          </tr>
        </table>
        <br>
        <p>
          Please log in to the Genesis Global CMS and action this follow-up immediately.
          If the worker needs assistance, please reach out directly.
        </p>
        <hr>
        <p style="color:#666;font-size:12px;">Genesis Global CMS — Automated Escalation Alert</p>
        </body></html>
        """
        plain_content = (
            f"ESCALATION: Overdue Follow-Up\n\n"
            f"Contact: {contact_name}\n"
            f"Assigned To: {worker_name}\n"
            f"Hours Overdue: {hours_overdue}\n\n"
            f"Please log in and action this follow-up immediately."
        )
        message = Mail(
            from_email=settings.FROM_EMAIL,
            to_emails=supervisor_email,
            subject=subject,
            html_content=html_content,
        )
        message.plain_text_content = plain_content
        return self._send(message)


# Singleton instance used throughout the application
sendgrid_client = SendGridClient()
