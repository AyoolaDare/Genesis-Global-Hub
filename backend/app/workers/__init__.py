"""
Genesis Global CMS — Celery Workers Package

Exports the configured Celery application instance.
"""

from app.workers.celery_app import celery_app

__all__ = ["celery_app"]
