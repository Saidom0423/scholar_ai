import os

# FORCE PURE PYTHON PROTOBUF: Python 3.14 has native incompatibilities with C-based protobuf extensions.
# Setting this environment variable forces google.protobuf to use pure Python, resolving 'TypeError: Metaclasses with custom tp_new are not supported'.
os.environ["PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION"] = "python"

from dotenv import load_dotenv

# Load .env file relative to the config.py directory
config_dir = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(config_dir, ".env"))

# General Settings
ENV = os.getenv("ENV", "local")  # "local" or "cloud"

# Database Settings
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./study_assistant.db")
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

# PDF Storage Settings
STORAGE_TYPE = os.getenv("STORAGE_TYPE", "local")
SUPABASE_URL = os.getenv("SUPABASE_URL", None)
SUPABASE_KEY = os.getenv("SUPABASE_KEY", None)
SUPABASE_BUCKET = os.getenv("SUPABASE_BUCKET", "pdfs")
UPLOAD_DIR = os.getenv("UPLOAD_DIR", "uploads")

# AI API Key (Gemini)
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", None)

# JWT / Security Settings
JWT_SECRET = os.getenv("JWT_SECRET", "super-secret-key-change-it-in-production-1234567890")
JWT_ALGORITHM = os.getenv("JWT_ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "1440")) # 1 day
