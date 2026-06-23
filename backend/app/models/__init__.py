"""SQLAlchemy model package.

Model modules are imported directly by schemas and services. Avoid eager imports
here so SQLAlchemy does not register the same table twice during app startup.
"""

__all__: list[str] = []
