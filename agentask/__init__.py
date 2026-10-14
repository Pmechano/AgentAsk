"""Independent, file-backed questions for local Windows/WSL agents."""

from .service import ask, read_response, start_question

__all__ = ["ask", "read_response", "start_question"]
