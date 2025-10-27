"""
GenAI Adapter for SnakeBridge - Google Gemini with Streaming

Specialized adapter for google-genai library providing:
- Simple text generation
- Streaming token-by-token generation
- Error handling for API keys
- Model shortcuts

Install: pip install google-genai==1.46.0
Requires: GEMINI_API_KEY environment variable
"""

import os
import logging
from typing import Optional, Iterator

try:
    from snakepit_bridge.base_adapter_threaded import ThreadSafeAdapter, tool
    HAS_SNAKEPIT = True
except ImportError:
    ThreadSafeAdapter = object
    HAS_SNAKEPIT = False

    def tool(description="", **kwargs):
        def decorator(func):
            return func
        return decorator

logger = logging.getLogger(__name__)


class GenAIAdapter(ThreadSafeAdapter):
    """
    Specialized adapter for Google GenAI library.

    Provides optimized integration with proper:
    - Client management
    - Streaming support
    - Error handling
    """

    def __init__(self):
        if HAS_SNAKEPIT:
            super().__init__()
        self.client = None
        self.initialized = False
        logger.info("GenAIAdapter initialized")

    def set_session_context(self, session_context):
        """Set session context."""
        self.session_context = session_context

    async def initialize(self):
        """Initialize GenAI client."""
        try:
            import google.genai as genai

            api_key = os.getenv("GEMINI_API_KEY")
            if not api_key:
                raise ValueError("GEMINI_API_KEY environment variable not set")

            self.client = genai.Client(api_key=api_key)
            self.initialized = True
            logger.info("GenAI client initialized")

        except Exception as e:
            logger.error(f"Failed to initialize GenAI: {e}")
            raise

    async def cleanup(self):
        """Cleanup resources."""
        self.client = None
        self.initialized = False
        logger.info("GenAI adapter cleaned up")

    def execute_tool(self, tool_name: str, arguments: dict, context):
        """Dispatch tool calls."""
        logger.info(f"!!! execute_tool CALLED: tool={tool_name}")

        # Delegate discovery to generic SnakeBridgeAdapter
        if tool_name == "describe_library":
            from snakebridge_adapter.adapter import SnakeBridgeAdapter
            generic = SnakeBridgeAdapter()
            return generic.describe_library(
                module_path=arguments.get("module_path"),
                discovery_depth=arguments.get("discovery_depth", 2)
            )
        elif tool_name == "call_python":
            from snakebridge_adapter.adapter import SnakeBridgeAdapter
            generic = SnakeBridgeAdapter()
            return generic.call_python(
                module_path=arguments.get("module_path"),
                function_name=arguments.get("function_name"),
                args=arguments.get("args"),
                kwargs=arguments.get("kwargs")
            )
        elif tool_name == "generate_text":
            return self.generate_text(
                model=arguments.get("model", "gemini-2.0-flash-exp"),
                prompt=arguments.get("prompt", "")
            )
        elif tool_name == "generate_text_stream":
            logger.info("!!! About to call generate_text_stream")
            result = self.generate_text_stream(
                model=arguments.get("model", "gemini-2.0-flash-exp"),
                prompt=arguments.get("prompt", "")
            )
            logger.info(f"!!! generate_text_stream returned: {type(result)}")
            return result
        else:
            return {"success": False, "error": f"Unknown tool: {tool_name}"}

    def _ensure_initialized(self):
        """Lazy initialization of GenAI client."""
        if not self.initialized:
            import asyncio
            try:
                asyncio.run(self.initialize())
            except RuntimeError:
                # Already in event loop, try sync init
                import google.genai as genai
                api_key = os.getenv("GEMINI_API_KEY")
                if not api_key:
                    raise ValueError("GEMINI_API_KEY environment variable not set")
                self.client = genai.Client(api_key=api_key)
                self.initialized = True
                logger.info("GenAI client initialized (sync)")

    @tool(description="Generate text with Gemini (non-streaming)")
    def generate_text(self, model: str, prompt: str) -> dict:
        """
        Generate text from Gemini model.

        Args:
            model: Model name (e.g., "gemini-2.0-flash-exp", "gemini-flash-lite-latest")
            prompt: Text prompt

        Returns:
            {"success": true, "text": "generated text..."}
        """
        try:
            self._ensure_initialized()
        except Exception as e:
            return {"success": False, "error": f"Failed to initialize: {str(e)}"}

        try:
            response = self.client.models.generate_content(
                model=model,
                contents=prompt
            )

            return {
                "success": True,
                "text": response.text,
                "model": model
            }

        except Exception as e:
            logger.error(f"GenAI generation error: {e}")
            return {
                "success": False,
                "error": str(e)
            }

    @tool(description="Generate text with streaming", supports_streaming=True)
    def generate_text_stream(self, model: str, prompt: str):
        """
        Stream text generation from Gemini.

        Args:
            model: Model name
            prompt: Text prompt

        Yields:
            {"chunk": "token..."} for each chunk
        """
        import asyncio

        logger.info("!!! generate_text_stream CALLED")

        try:
            logger.info("!!! About to initialize")
            self._ensure_initialized()
            logger.info("!!! Initialized successfully")
        except Exception as e:
            logger.error(f"!!! Init failed: {e}")
            yield {"success": False, "error": f"Failed to initialize: {str(e)}"}
            return

        try:
            # The GenAI library's generate_content_stream returns an async generator
            # We need to consume it in an event loop and yield synchronously

            # Get or create event loop
            try:
                loop = asyncio.get_event_loop()
            except RuntimeError:
                loop = asyncio.new_event_loop()
                asyncio.set_event_loop(loop)

            # Create the async generator
            async_response = self.client.models.generate_content_stream(
                model=model,
                contents=prompt
            )

            logger.info(f"DEBUG: async_response type: {type(async_response)}")
            logger.info(f"DEBUG: has __aiter__: {hasattr(async_response, '__aiter__')}")
            logger.info(f"DEBUG: has __iter__: {hasattr(async_response, '__iter__')}")

            # Consume it synchronously using run_until_complete
            while True:
                try:
                    chunk = loop.run_until_complete(async_response.__anext__())
                    if hasattr(chunk, 'text') and chunk.text:
                        yield {"chunk": chunk.text}
                except StopAsyncIteration:
                    break

            yield {"success": True, "done": True}

        except Exception as e:
            logger.error(f"GenAI streaming error: {e}")
            yield {"success": False, "error": str(e)}
