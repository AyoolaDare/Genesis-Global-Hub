"""
Genesis Global CMS — External Integrations Package

Exposes singleton clients for:
  - Flutterwave (payments)
  - Termii (SMS / WhatsApp)
  - SendGrid (email)
"""

from app.integrations.flutterwave import flutterwave
from app.integrations.termii import termii
from app.integrations.sendgrid import sendgrid_client

__all__ = ["flutterwave", "termii", "sendgrid_client"]
